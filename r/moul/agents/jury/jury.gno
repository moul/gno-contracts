// Package jury is a commit-reveal adversarial review protocol for disputes
// over agent work.
//
// The hard part of an agent economy is not paying agents — it is deciding
// what happens when an agent's output is disputed. This realm runs a small
// jury: a fixed panel of reviewers each *commit* to a hidden verdict, then
// *reveal* it. Commit-reveal means no juror can copy another's vote or be
// swayed after seeing the tally; every verdict is locked in blind.
//
// The subject of a case is an opaque string — a receipt sequence, a claim
// id, an off-chain artifact hash — so this realm composes with the receipt
// and gnomem demos without depending on them.
//
// Bonding and slashing (a juror stakes coins, loses them for provably bad
// verdicts) are the natural economic layer on top; this demo shows the
// mechanism without the money.
package jury

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/moul/agents/commit/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Phase is a case's position in the commit-reveal lifecycle.
type Phase string

const (
	PhaseCommit Phase = "commit"
	PhaseReveal Phase = "reveal"
	PhaseClosed Phase = "closed"
)

// Juror is one panelist and their (eventually revealed) verdict.
type Juror struct {
	Addr       address
	Commitment string // commit.Verdict(verdict, salt)
	Committed  bool
	Revealed   bool
	Verdict    bool // meaningful once Revealed
	Height     int64
}

// Case is a single dispute under review by a fixed panel.
type Case struct {
	ID       uint64
	Subject  string // opaque reference to the disputed thing
	Opener   address
	Phase    Phase
	Jurors   []*Juror
	OpenedAt int64
	Outcome  string // "upheld" | "rejected" | "tie" once closed
	Yes      int
	No       int
}

var cases []*Case // index 0 => ID 1

// The bounds on what a wallet may open. OpenCase is callable by anyone, so
// without them the case list and every panel grow without limit, and so does
// the index page that renders them.
const (
	MaxCases    = 1000
	MaxJurors   = 25
	MaxSubject  = 200 // bytes
	IndexRecent = 50  // cases the index lists, newest first

	MaxCommitment = 128 // bytes; commit.Verdict returns 64
)

// OpenCase starts a dispute with a fixed panel of jurors, given as
// comma-separated addresses. An odd panel size avoids ties; duplicates and
// invalid addresses are rejected.
//
// The panel is a string, not a []address, because MsgCall carries every
// argument as a string and the VM decodes no slice but []byte: a []address
// parameter made this function unreachable from any wallet.
func OpenCase(cur realm, subject, jurorsCSV string) uint64 {
	opener := caller(cur)
	// Checked after sanitizing: a subject of only zero-width runes is not empty
	// as bytes, and renders as nothing.
	assert(strings.TrimSpace(ui.Inline(subject)) != "", "empty subject")
	assert(len(subject) <= MaxSubject, "subject too long")
	assert(len(cases) < MaxCases, "the jury is full")
	jurors := parseJurors(jurorsCSV)
	assert(len(jurors) >= 1, "need at least one juror")
	assert(len(jurors) <= MaxJurors, "panel too large")

	seen := make(map[string]bool)
	panel := make([]*Juror, 0, len(jurors))
	for _, j := range jurors {
		key := j.String()
		assert(!seen[key], "duplicate juror: "+key)
		seen[key] = true
		panel = append(panel, &Juror{Addr: j})
	}

	id := uint64(len(cases)) + 1
	cases = append(cases, &Case{
		ID:       id,
		Subject:  subject,
		Opener:   opener,
		Phase:    PhaseCommit,
		Jurors:   panel,
		OpenedAt: runtime.ChainHeight(),
	})
	chain.Emit("CaseOpened", "id", ufmt.Sprintf("%d", id), "jurors", ufmt.Sprintf("%d", len(panel)))
	return id
}

// Commit locks in a juror's hidden verdict. commitment must equal
// commit.Verdict(verdict, salt) — computed off-chain. When the last juror
// commits, the case advances to the reveal phase automatically.
func Commit(cur realm, caseID uint64, commitment string) {
	who := caller(cur)
	c := mustCase(caseID)
	assert(c.Phase == PhaseCommit, "not in commit phase")
	assert(commitment != "", "empty commitment")
	// commit.Verdict is a hex sha256; anything longer is not one, and would be
	// stored and compared on every later Commit in the case.
	assert(len(commitment) <= MaxCommitment, "commitment too long")
	j := mustJuror(c, who)
	assert(!j.Committed, "already committed")
	// Every commitment is public through Get, so without this a juror could
	// commit a copy of another's hash, then reveal the same (verdict, salt)
	// once the first juror's reveal puts it in a transaction. Refusing a
	// repeat makes a copied commitment unrevealable.
	for _, other := range c.Jurors {
		assert(!other.Committed || other.Commitment != commitment, "commitment already used in this case")
	}
	j.Commitment = commitment
	j.Committed = true
	j.Height = runtime.ChainHeight()

	if allCommitted(c) {
		c.Phase = PhaseReveal
		chain.Emit("CasePhase", "id", ufmt.Sprintf("%d", caseID), "phase", string(PhaseReveal))
	}
}

// Reveal opens a juror's verdict. The (verdict, salt) must reproduce the
// commitment made earlier, or the reveal is rejected. When the last juror
// reveals, the case closes and the majority outcome is recorded.
func Reveal(cur realm, caseID uint64, verdict bool, salt string) {
	who := caller(cur)
	c := mustCase(caseID)
	assert(c.Phase == PhaseReveal, "not in reveal phase")
	j := mustJuror(c, who)
	assert(j.Committed && !j.Revealed, "nothing to reveal")
	assert(commit.Verdict(verdict, salt) == j.Commitment, "reveal does not match commitment")

	j.Revealed = true
	j.Verdict = verdict
	if verdict {
		c.Yes++
	} else {
		c.No++
	}
	chain.Emit("VerdictRevealed", "id", ufmt.Sprintf("%d", caseID), "verdict", boolStr(verdict))

	if allRevealed(c) {
		closeCase(c)
	}
}

// ---- read-only API ----

// Get returns a copy of a case (jurors flattened separately via Jury).
func Get(caseID uint64) Case { return *mustCase(caseID) }

// Outcome returns the recorded outcome, or "" if the case is still open.
func Outcome(caseID uint64) string { return mustCase(caseID).Outcome }

// Count returns the number of cases.
func Count() int { return len(cases) }

// ---- internal ----

func closeCase(c *Case) {
	switch {
	case c.Yes > c.No:
		c.Outcome = "upheld"
	case c.No > c.Yes:
		c.Outcome = "rejected"
	default:
		c.Outcome = "tie"
	}
	c.Phase = PhaseClosed
	chain.Emit("CaseClosed", "id", ufmt.Sprintf("%d", c.ID), "outcome", c.Outcome)
}

func allCommitted(c *Case) bool {
	for _, j := range c.Jurors {
		if !j.Committed {
			return false
		}
	}
	return true
}

func allRevealed(c *Case) bool {
	for _, j := range c.Jurors {
		if !j.Revealed {
			return false
		}
	}
	return true
}

func mustCase(id uint64) *Case {
	assert(id >= 1 && id <= uint64(len(cases)), "unknown case")
	return cases[id-1]
}

func mustJuror(c *Case, addr address) *Juror {
	for _, j := range c.Jurors {
		if j.Addr == addr {
			return j
		}
	}
	panic("caller is not on this jury")
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

// Render shows all cases, or one case's panel + tally at :<id>.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderCase(parseID(path))
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Agent Jury\n\n")
	sb.WriteString("_Who checks the agents?_ Blind commit-reveal review by a fixed panel.\n\n")
	if len(cases) == 0 {
		sb.WriteString("_No cases yet._\n")
		return sb.String()
	}
	if len(cases) > IndexRecent {
		sb.WriteString(ufmt.Sprintf("The %d most recent of %d cases, newest first.\n\n", IndexRecent, len(cases)))
	}
	sb.WriteString("| # | Subject | Phase | ✅ | ❌ | Outcome |\n")
	sb.WriteString("|---|---|---|---|---|---|\n")
	// Newest first, and only the last IndexRecent: the page has to render at
	// MaxCases too.
	for i := len(cases) - 1; i >= 0 && i >= len(cases)-IndexRecent; i-- {
		c := cases[i]
		out := c.Outcome
		if out == "" {
			out = "—"
		}
		sb.WriteString(ufmt.Sprintf("| [%d](/r/moul/agents/jury/v0:%d) | %s | %s | %d | %d | %s |\n",
			c.ID, c.ID, ui.Cell(c.Subject), string(c.Phase), c.Yes, c.No, out))
	}
	return sb.String()
}

func renderCase(id uint64) string {
	c := mustCase(id)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Case #%d\n\n", c.ID))
	sb.WriteString(ufmt.Sprintf("- **Subject:** %s\n", ui.Inline(c.Subject)))
	sb.WriteString(ufmt.Sprintf("- **Phase:** %s\n", string(c.Phase)))
	sb.WriteString(ufmt.Sprintf("- **Opened by:** %s at height %d\n", short(c.Opener), c.OpenedAt))
	if c.Outcome != "" {
		sb.WriteString(ufmt.Sprintf("- **Outcome:** **%s** (%d ✅ / %d ❌)\n", c.Outcome, c.Yes, c.No))
	}
	sb.WriteString("\n## Panel\n\n")
	sb.WriteString("| Juror | Committed | Revealed | Verdict | Dissent |\n|---|---|---|---|---|\n")
	majority := c.Yes >= c.No // for dissent marking once closed
	for _, j := range c.Jurors {
		verdict, dissent := "—", ""
		if j.Revealed {
			verdict = boolStr(j.Verdict)
			if c.Phase == PhaseClosed && c.Outcome != "tie" && j.Verdict != majority {
				dissent = "⚠"
			}
		}
		sb.WriteString(ufmt.Sprintf("| %s | %t | %t | %s | %s |\n",
			short(j.Addr), j.Committed, j.Revealed, verdict, dissent))
	}
	return sb.String()
}

func parseID(s string) uint64 {
	var n uint64
	for i := 0; i < len(s); i++ {
		ch := s[i]
		assert(ch >= '0' && ch <= '9', "invalid case path: "+s)
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

// parseJurors splits a comma-separated panel, trimming spaces around each
// address and refusing an empty or invalid one.
func parseJurors(csv string) []address {
	var out []address
	for _, part := range strings.Split(csv, ",") {
		a := address(strings.TrimSpace(part))
		assert(a.IsValid(), "invalid juror address: "+string(a))
		out = append(out, a)
	}
	return out
}

// caller is the address that crossed into this realm, after checking that the
// realm token is this frame's own. Every entry point reads it first, before
// any other work.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("jury: spoofed realm")
	}
	return cur.Previous().Address()
}
