// Package maintainer models an AI agent stewarding a versioned on-chain
// package — without ever letting it deploy on its own authority.
//
// The agent can do the tedious, valuable parts: open a version proposal,
// collect reviews, record CI test attestations, write release notes,
// deprecate a vulnerable version, keep a compatibility matrix. What it
// cannot do is ship. Approval is gated by an explicit, machine-checked
// policy:
//
//	tests pass  AND  ≥ MinReviewers independent reviews  AND
//	every review scores ≥ MinScore  AND  the challenge window has elapsed
//
// This is the difference between "an agent with commit access" and "an
// agent that drives a process a human (or a DAO, or a policy) still gates."
// The realm records *approved* releases; the actual package publish is a
// separate, deliberately human/authority step.
package maintainer

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

const (
	MinReviewers = 2  // independent reviews required
	MinScore     = 80 // minimum score every reviewer must give
)

// Review is one reviewer's score for a proposal.
type Review struct {
	By     address
	Score  uint8 // 0..100
	Note   string
	Height int64
}

// Proposal is a candidate new version working its way toward approval.
type Proposal struct {
	ID             uint64
	Version        string
	ArtifactHash   string // commitment to the package source
	Proposer       address
	Reviews        []Review
	TestsPass      bool
	TestsAttestor  address
	OpenedAt       int64
	ChallengeUntil int64 // approval blocked until height passes this
	Approved       bool
	ApprovedAt     int64
}

// Release is an approved (and possibly later deprecated) version.
type Release struct {
	Version          string
	ArtifactHash     string
	ReleasedAt       int64
	Deprecated       bool
	DeprecatedReason string
}

var (
	proposals []*Proposal        // index 0 => ID 1
	releases  []*Release         // in release order
	byVersion = map[string]*Release{}
)

// Propose opens a version proposal with a challenge window of the given
// number of blocks (during which reviews accrue and approval is blocked).
func Propose(cur realm, version, artifactHash string, challengeBlocks int64) uint64 {
	assert(version != "", "empty version")
	assert(artifactHash != "", "empty artifact hash")
	assert(challengeBlocks >= 0, "negative challenge window")
	_, exists := byVersion[version]
	assert(!exists, "version already released: "+version)

	id := uint64(len(proposals)) + 1
	h := runtime.ChainHeight()
	proposals = append(proposals, &Proposal{
		ID:             id,
		Version:        version,
		ArtifactHash:   artifactHash,
		Proposer:       cur.Previous().Address(),
		OpenedAt:       h,
		ChallengeUntil: h + challengeBlocks,
	})
	chain.Emit("VersionProposed", "id", ufmt.Sprintf("%d", id), "version", version)
	return id
}

// AddReview records a reviewer's score. Reviewers must be independent of the
// proposer, and each address reviews at most once.
func AddReview(cur realm, propID uint64, score uint8, note string) {
	p := mustProposal(propID)
	assert(!p.Approved, "proposal already approved")
	assert(score <= 100, "score must be 0..100")
	reviewer := cur.Previous().Address()
	assert(reviewer != p.Proposer, "proposer cannot review own proposal")
	for _, r := range p.Reviews {
		assert(r.By != reviewer, "reviewer already reviewed")
	}
	p.Reviews = append(p.Reviews, Review{By: reviewer, Score: score, Note: note, Height: runtime.ChainHeight()})
	chain.Emit("VersionReviewed", "id", ufmt.Sprintf("%d", propID), "score", ufmt.Sprintf("%d", score))
}

// AttestTests records whether CI's test suite passed for the proposal.
func AttestTests(cur realm, propID uint64, pass bool) {
	p := mustProposal(propID)
	assert(!p.Approved, "proposal already approved")
	p.TestsPass = pass
	p.TestsAttestor = cur.Previous().Address()
	chain.Emit("TestsAttested", "id", ufmt.Sprintf("%d", propID), "pass", boolStr(pass))
}

// Approve promotes a proposal to a release iff every policy condition holds.
// It panics with the first unmet condition — the policy is the gate, not a
// suggestion.
func Approve(cur realm, propID uint64) {
	p := mustProposal(propID)
	assert(!p.Approved, "proposal already approved")
	assert(p.TestsPass, "policy: tests have not passed")
	assert(len(p.Reviews) >= MinReviewers, ufmt.Sprintf("policy: need %d reviews, have %d", MinReviewers, len(p.Reviews)))
	for _, r := range p.Reviews {
		assert(r.Score >= MinScore, ufmt.Sprintf("policy: review from %s scored %d < %d", short(r.By), r.Score, MinScore))
	}
	assert(runtime.ChainHeight() > p.ChallengeUntil, "policy: challenge window still open")

	p.Approved = true
	p.ApprovedAt = runtime.ChainHeight()
	rel := &Release{Version: p.Version, ArtifactHash: p.ArtifactHash, ReleasedAt: p.ApprovedAt}
	releases = append(releases, rel)
	byVersion[p.Version] = rel
	chain.Emit("VersionApproved", "id", ufmt.Sprintf("%d", propID), "version", p.Version)
}

// Deprecate flags a released version (e.g. a vulnerability was found).
func Deprecate(cur realm, version, reason string) {
	rel, ok := byVersion[version]
	assert(ok, "unknown version: "+version)
	rel.Deprecated = true
	rel.DeprecatedReason = reason
	chain.Emit("VersionDeprecated", "version", version)
}

// ---- read-only API ----

// LatestVersion returns the most recently released version, or "".
func LatestVersion() string {
	if len(releases) == 0 {
		return ""
	}
	return releases[len(releases)-1].Version
}

// IsDeprecated reports whether a released version is deprecated.
func IsDeprecated(version string) bool {
	rel, ok := byVersion[version]
	return ok && rel.Deprecated
}

// GetProposal returns a copy of a proposal.
func GetProposal(id uint64) Proposal { return *mustProposal(id) }

// ---- internal ----

func mustProposal(id uint64) *Proposal {
	assert(id >= 1 && id <= uint64(len(proposals)), "unknown proposal")
	return proposals[id-1]
}

func boolStr(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

func assert(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}

// Render shows the release matrix + open proposals, or one proposal at :<id>.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderProposal(parseID(path))
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Agent Package Maintainer\n\n")
	sb.WriteString(ufmt.Sprintf("_The agent drives the process; the policy still gates the ship._ "))
	sb.WriteString(ufmt.Sprintf("Approval needs tests + ≥%d reviews each ≥%d + an elapsed challenge window.\n\n", MinReviewers, MinScore))

	sb.WriteString("## Releases\n\n")
	if len(releases) == 0 {
		sb.WriteString("_No releases yet._\n\n")
	} else {
		sb.WriteString("| Version | Released @ | State |\n|---|---|---|\n")
		for _, r := range releases {
			st := "✅ current"
			if r.Deprecated {
				st = "⚠ deprecated: " + r.DeprecatedReason
			}
			sb.WriteString(ufmt.Sprintf("| %s | %d | %s |\n", r.Version, r.ReleasedAt, st))
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Proposals\n\n")
	if len(proposals) == 0 {
		sb.WriteString("_None._\n")
		return sb.String()
	}
	sb.WriteString("| # | Version | Tests | Reviews | Approved |\n|---|---|---|---|---|\n")
	for _, p := range proposals {
		sb.WriteString(ufmt.Sprintf("| [%d](/r/moul/agents/maintainer/v0:%d) | %s | %s | %d | %t |\n",
			p.ID, p.ID, p.Version, boolStr(p.TestsPass), len(p.Reviews), p.Approved))
	}
	return sb.String()
}

func renderProposal(id uint64) string {
	p := mustProposal(id)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Proposal #%d — %s\n\n", p.ID, p.Version))
	sb.WriteString(ufmt.Sprintf("- **Artifact:** `%s`\n", shortHash(p.ArtifactHash)))
	sb.WriteString(ufmt.Sprintf("- **Proposer:** %s\n", short(p.Proposer)))
	sb.WriteString(ufmt.Sprintf("- **Tests pass:** %t\n", p.TestsPass))
	sb.WriteString(ufmt.Sprintf("- **Challenge window until height:** %d (now %d)\n", p.ChallengeUntil, runtime.ChainHeight()))
	sb.WriteString(ufmt.Sprintf("- **Approved:** %t\n\n", p.Approved))

	sb.WriteString(ufmt.Sprintf("## Policy checklist\n\n"))
	sb.WriteString(check(p.TestsPass, "tests pass"))
	sb.WriteString(check(len(p.Reviews) >= MinReviewers, ufmt.Sprintf("≥%d independent reviews (have %d)", MinReviewers, len(p.Reviews))))
	minOK := true
	for _, r := range p.Reviews {
		if r.Score < MinScore {
			minOK = false
		}
	}
	sb.WriteString(check(len(p.Reviews) > 0 && minOK, ufmt.Sprintf("every review ≥%d", MinScore)))
	sb.WriteString(check(runtime.ChainHeight() > p.ChallengeUntil, "challenge window elapsed"))
	sb.WriteString("\n")

	sb.WriteString(ufmt.Sprintf("## Reviews (%d)\n\n", len(p.Reviews)))
	if len(p.Reviews) == 0 {
		sb.WriteString("_None._\n")
		return sb.String()
	}
	sb.WriteString("| Reviewer | Score | Note | Height |\n|---|---|---|---|\n")
	for _, r := range p.Reviews {
		sb.WriteString(ufmt.Sprintf("| %s | %d | %s | %d |\n", short(r.By), r.Score, r.Note, r.Height))
	}
	return sb.String()
}

func check(ok bool, label string) string {
	box := "❌"
	if ok {
		box = "✅"
	}
	return ufmt.Sprintf("- %s %s\n", box, label)
}

func parseID(s string) uint64 {
	var n uint64
	for i := 0; i < len(s); i++ {
		ch := s[i]
		assert(ch >= '0' && ch <= '9', "invalid proposal path: "+s)
		n = n*10 + uint64(ch-'0')
	}
	return n
}

func short(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return s
	}
	return s[:8] + "…" + s[len(s)-4:]
}

func shortHash(s string) string {
	if len(s) <= 12 {
		return s
	}
	return s[:6] + "…" + s[len(s)-4:]
}
