// Package gnomem is a shared, contestable memory for multiple agents.
//
// Most "agent memory" products store text and retrieve similar chunks.
// That works for one agent talking to itself. It breaks the moment several
// independent agents — possibly run by different people, on different
// models — must maintain a *shared* understanding of the same world and
// sometimes disagree about it.
//
// gnomem models memory not as text but as a graph of structured claims.
// Each claim is a (subject, predicate, object) triple with an author,
// evidence and a confidence. Other agents can support it, contest it, add
// evidence, supersede it with a better claim, or trigger adjudication. No
// agent can silently erase an inconvenient finding: claims can be
// superseded or retracted, but the history stays visible and ordered.
//
// The point of the demo is the structure, not access control: anyone may
// write. Gating *who* may write to which claim is exactly what the
// capability-wallet demo adds on top.
package gnomem

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

// Status is a claim's position in the argument lifecycle.
type Status string

const (
	StatusProposed   Status = "proposed"   // asserted, no endorsements yet
	StatusSupported  Status = "supported"  // has support, no live contest
	StatusContested  Status = "contested"  // at least one live contest
	StatusAccepted   Status = "accepted"   // adjudicated true (terminal)
	StatusRetracted  Status = "retracted"  // adjudicated false / withdrawn (terminal)
	StatusSuperseded Status = "superseded" // replaced by a better claim (terminal)
)

// Endorsement is a support or contest signal from one agent.
type Endorsement struct {
	Agent      address
	Confidence uint8 // 0..100
	Note       string
	Height     int64
}

// Evidence points at off-chain material backing (or refuting) a claim.
type Evidence struct {
	By     address
	Kind   string // "report", "exploit", "dataset", "citation", ...
	Hash   string // commitment to the off-chain artifact
	Height int64
}

// Claim is one node in the shared memory graph.
type Claim struct {
	ID           uint64
	Subject      string
	Predicate    string
	Object       string
	Author       address
	Confidence   uint8
	Status       Status
	CreatedAt    int64
	Supports     []Endorsement
	Contests     []Endorsement
	Evidence     []Evidence
	SupersededBy uint64 // 0 if none
	Supersedes   uint64 // 0 if none
	Resolver     address
	ResolvedAt   int64
}

var claims []*Claim // index 0 => ID 1

// ProposeClaim asserts a new (subject, predicate, object) triple.
func ProposeClaim(cur realm, subject, predicate, object, evidenceHash string, confidence uint8) uint64 {
	assert(subject != "" && predicate != "" && object != "", "empty triple field")
	assertConfidence(confidence)

	id := uint64(len(claims)) + 1
	c := &Claim{
		ID:         id,
		Subject:    subject,
		Predicate:  predicate,
		Object:     object,
		Author:     cur.Previous().Address(),
		Confidence: confidence,
		Status:     StatusProposed,
		CreatedAt:  runtime.ChainHeight(),
	}
	if evidenceHash != "" {
		c.Evidence = append(c.Evidence, Evidence{
			By: c.Author, Kind: "initial", Hash: evidenceHash, Height: c.CreatedAt,
		})
	}
	claims = append(claims, c)
	chain.Emit("ClaimProposed", "id", ufmt.Sprintf("%d", id), "subject", subject, "predicate", predicate)
	return id
}

// SupportClaim endorses a claim. Support never overrides a live contest —
// a contested claim stays contested until adjudicated.
func SupportClaim(cur realm, id uint64, confidence uint8, note string) {
	c := mustOpen(id)
	assertConfidence(confidence)
	c.Supports = append(c.Supports, Endorsement{
		Agent: cur.Previous().Address(), Confidence: confidence, Note: note, Height: runtime.ChainHeight(),
	})
	if c.Status == StatusProposed {
		c.Status = StatusSupported
	}
	chain.Emit("ClaimSupported", "id", ufmt.Sprintf("%d", id))
}

// ContestClaim challenges a claim, optionally attaching refuting evidence.
func ContestClaim(cur realm, id uint64, note, evidenceHash string) {
	c := mustOpen(id)
	agent := cur.Previous().Address()
	h := runtime.ChainHeight()
	c.Contests = append(c.Contests, Endorsement{
		Agent: agent, Confidence: 0, Note: note, Height: h,
	})
	if evidenceHash != "" {
		c.Evidence = append(c.Evidence, Evidence{By: agent, Kind: "refutation", Hash: evidenceHash, Height: h})
	}
	c.Status = StatusContested
	chain.Emit("ClaimContested", "id", ufmt.Sprintf("%d", id))
}

// AddEvidence attaches supporting or contextual off-chain material.
func AddEvidence(cur realm, id uint64, kind, hash string) {
	c := mustOpen(id)
	assert(hash != "", "empty evidence hash")
	c.Evidence = append(c.Evidence, Evidence{
		By: cur.Previous().Address(), Kind: kind, Hash: hash, Height: runtime.ChainHeight(),
	})
}

// SupersedeClaim replaces an open claim with a new one. The old claim is
// marked superseded (terminal) and linked to its replacement, so the
// correction is visible rather than a silent overwrite.
func SupersedeClaim(cur realm, oldID uint64, subject, predicate, object, evidenceHash string, confidence uint8) uint64 {
	old := mustOpen(oldID)
	newID := ProposeClaim(cur, subject, predicate, object, evidenceHash, confidence)
	newC := claims[newID-1]
	newC.Supersedes = oldID
	old.Status = StatusSuperseded
	old.SupersededBy = newID
	chain.Emit("ClaimSuperseded", "old", ufmt.Sprintf("%d", oldID), "new", ufmt.Sprintf("%d", newID))
	return newID
}

// ResolveClaim adjudicates an open claim as accepted (true) or retracted
// (false/withdrawn). The resolver's address is recorded — resolution is
// itself a provenance-bearing act, not an anonymous verdict.
func ResolveClaim(cur realm, id uint64, accepted bool) {
	c := mustOpen(id)
	if accepted {
		c.Status = StatusAccepted
	} else {
		c.Status = StatusRetracted
	}
	c.Resolver = cur.Previous().Address()
	c.ResolvedAt = runtime.ChainHeight()
	chain.Emit("ClaimResolved", "id", ufmt.Sprintf("%d", id), "status", string(c.Status))
}

// ---- read-only API ----

// Get returns a copy of a claim by id.
func Get(id uint64) Claim { return *mustGet(id) }

// Count returns the number of claims in the graph.
func Count() int { return len(claims) }

// IsOpen reports whether a claim can still be supported/contested/resolved.
func IsOpen(id uint64) bool { return isOpen(mustGet(id).Status) }

// ---- internal ----

func isOpen(s Status) bool {
	return s == StatusProposed || s == StatusSupported || s == StatusContested
}

func mustGet(id uint64) *Claim {
	assert(id >= 1 && id <= uint64(len(claims)), "unknown claim")
	return claims[id-1]
}

func mustOpen(id uint64) *Claim {
	c := mustGet(id)
	assert(isOpen(c.Status), "claim is resolved (terminal): "+string(c.Status))
	return c
}

func assertConfidence(c uint8) { assert(c <= 100, "confidence must be 0..100") }

func assert(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}

// Render shows the full graph, or one claim's argument tree at :<id>.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderClaim(parseID(path))
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# GnoMem — Contested Shared Memory\n\n")
	sb.WriteString(ufmt.Sprintf("A graph of %d structured claim(s) maintained by multiple agents.\n\n", len(claims)))
	if len(claims) == 0 {
		sb.WriteString("_No claims yet._\n")
		return sb.String()
	}
	sb.WriteString("| # | Claim | Status | ✋ support | ⚔ contest |\n")
	sb.WriteString("|---|---|---|---|---|\n")
	for _, c := range claims {
		sb.WriteString(ufmt.Sprintf("| [%d](/r/moul/agents/gnomem/v0:%d) | %s | %s | %d | %d |\n",
			c.ID, c.ID, triple(c), statusBadge(c.Status), len(c.Supports), len(c.Contests)))
	}
	return sb.String()
}

func renderClaim(id uint64) string {
	c := mustGet(id)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Claim #%d\n\n", c.ID))
	sb.WriteString(ufmt.Sprintf("> **%s**\n\n", triple(c)))
	sb.WriteString(ufmt.Sprintf("- **Status:** %s\n", statusBadge(c.Status)))
	sb.WriteString(ufmt.Sprintf("- **Author:** %s\n", short(c.Author)))
	sb.WriteString(ufmt.Sprintf("- **Author confidence:** %d/100\n", c.Confidence))
	sb.WriteString(ufmt.Sprintf("- **Created at height:** %d\n", c.CreatedAt))
	if c.Supersedes != 0 {
		sb.WriteString(ufmt.Sprintf("- **Supersedes:** [#%d](/r/moul/agents/gnomem/v0:%d)\n", c.Supersedes, c.Supersedes))
	}
	if c.SupersededBy != 0 {
		sb.WriteString(ufmt.Sprintf("- **Superseded by:** [#%d](/r/moul/agents/gnomem/v0:%d)\n", c.SupersededBy, c.SupersededBy))
	}
	if c.ResolvedAt != 0 {
		sb.WriteString(ufmt.Sprintf("- **Resolved by:** %s at height %d\n", short(c.Resolver), c.ResolvedAt))
	}
	sb.WriteString("\n")

	sb.WriteString(ufmt.Sprintf("## ✋ Support (%d)\n\n", len(c.Supports)))
	renderEndorsements(&sb, c.Supports)
	sb.WriteString(ufmt.Sprintf("## ⚔ Contest (%d)\n\n", len(c.Contests)))
	renderEndorsements(&sb, c.Contests)

	sb.WriteString(ufmt.Sprintf("## 📎 Evidence (%d)\n\n", len(c.Evidence)))
	if len(c.Evidence) == 0 {
		sb.WriteString("_None._\n")
	} else {
		sb.WriteString("| By | Kind | Commitment | Height |\n|---|---|---|---|\n")
		for _, e := range c.Evidence {
			sb.WriteString(ufmt.Sprintf("| %s | %s | `%s` | %d |\n", short(e.By), e.Kind, shortHash(e.Hash), e.Height))
		}
	}
	return sb.String()
}

func renderEndorsements(sb *strings.Builder, es []Endorsement) {
	if len(es) == 0 {
		sb.WriteString("_None._\n\n")
		return
	}
	sb.WriteString("| Agent | Confidence | Note | Height |\n|---|---|---|---|\n")
	for _, e := range es {
		sb.WriteString(ufmt.Sprintf("| %s | %d | %s | %d |\n", short(e.Agent), e.Confidence, e.Note, e.Height))
	}
	sb.WriteString("\n")
}

func triple(c *Claim) string {
	return ufmt.Sprintf("%s — %s — %s", c.Subject, c.Predicate, c.Object)
}

func statusBadge(s Status) string {
	switch s {
	case StatusAccepted:
		return "✅ accepted"
	case StatusRetracted:
		return "🚫 retracted"
	case StatusSuperseded:
		return "♻️ superseded"
	case StatusContested:
		return "⚔ contested"
	case StatusSupported:
		return "✋ supported"
	default:
		return "· proposed"
	}
}

func parseID(s string) uint64 {
	var n uint64
	for i := 0; i < len(s); i++ {
		c := s[i]
		assert(c >= '0' && c <= '9', "invalid claim path: "+s)
		n = n*10 + uint64(c-'0')
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
