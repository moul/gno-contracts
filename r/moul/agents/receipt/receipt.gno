// Package receipt is an append-only log of agent execution receipts.
//
// The thesis: provenance is not correctness. A chain can prove *who*
// committed to an output, *when*, that the bytes have not changed since,
// and *what* was staked or attested — but it cannot, by itself, prove the
// output was any good. Correctness comes from an external validation
// mechanism.
//
// So a receipt stores commitments (hashes) to the task, inputs, outputs,
// tool calls and runtime, never the raw data — that lives off-chain. The
// realm then lets independent validators attach attestations: "I re-ran
// this and it reproduced", "the tests pass", "the output matches the
// commitment", or "rejected". The receipt's trust level is exactly the sum
// of the attestations it has collected, and nothing more.
package receipt

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

// Verdicts a validator can record against a receipt.
const (
	VerdictReproduced   = "reproduced"    // re-ran and got the same output commitment
	VerdictTestsPass    = "tests-pass"    // the referenced test suite passed
	VerdictOutputMatch  = "output-match"  // output matches its commitment
	VerdictPolicyOK     = "policy-ok"     // no forbidden tool / policy respected
	VerdictRejected     = "rejected"      // the work is wrong or invalid
)

// Attestation is an independent validator's verdict on a receipt.
type Attestation struct {
	Validator address
	Verdict   string
	Note      string
	Height    int64
}

// Receipt commits to one agent action. Every field except Attestations is
// immutable once recorded.
type Receipt struct {
	Seq              uint64
	Agent            string // agent id (e.g. a gno.land/r/moul/agents/passport/v0 id)
	TaskHash         string // commitment to the task spec
	InputCommitment  string
	OutputCommitment string
	RuntimeID        string // which runtime/model produced it
	PolicyVersion    string // policy in force at execution time
	ToolCallsRoot    string // root hash over the tool-call trace
	HumanIntervened  bool
	Author           address
	Height           int64
	Attestations     []Attestation
}

var receipts []*Receipt // index 0 => Seq 1

// Record appends a new execution receipt and returns its sequence number.
// The caller commits to opaque hashes; the realm never sees raw payloads.
func Record(
	cur realm,
	agent, taskHash, inputCommitment, outputCommitment,
	runtimeID, policyVersion, toolCallsRoot string,
	humanIntervened bool,
) uint64 {
	assert(agent != "", "empty agent id")
	assert(taskHash != "", "empty task hash")
	assert(outputCommitment != "", "empty output commitment")

	seq := uint64(len(receipts)) + 1
	r := &Receipt{
		Seq:              seq,
		Agent:            agent,
		TaskHash:         taskHash,
		InputCommitment:  inputCommitment,
		OutputCommitment: outputCommitment,
		RuntimeID:        runtimeID,
		PolicyVersion:    policyVersion,
		ToolCallsRoot:    toolCallsRoot,
		HumanIntervened:  humanIntervened,
		Author:           cur.Previous().Address(),
		Height:           runtime.ChainHeight(),
	}
	receipts = append(receipts, r)
	chain.Emit("ReceiptRecorded",
		"seq", ufmt.Sprintf("%d", seq),
		"agent", agent,
		"output", outputCommitment,
	)
	return seq
}

// Attest attaches an independent validator's verdict to a receipt. The same
// validator cannot attest twice; the author of a receipt cannot attest to
// their own work (self-attestation proves nothing).
func Attest(cur realm, seq uint64, verdict, note string) {
	r := mustGet(seq)
	validator := cur.Previous().Address()
	assert(validator != r.Author, "author cannot attest to their own receipt")
	assertVerdict(verdict)
	for _, a := range r.Attestations {
		assert(a.Validator != validator, "validator already attested")
	}
	r.Attestations = append(r.Attestations, Attestation{
		Validator: validator,
		Verdict:   verdict,
		Note:      note,
		Height:    runtime.ChainHeight(),
	})
	chain.Emit("ReceiptAttested",
		"seq", ufmt.Sprintf("%d", seq),
		"validator", validator.String(),
		"verdict", verdict,
	)
}

// ---- read-only API ----

// Get returns a copy of a receipt by sequence number.
func Get(seq uint64) Receipt { return *mustGet(seq) }

// Count returns the number of receipts recorded.
func Count() int { return len(receipts) }

// Confirmations returns (positive, rejections) attestation counts. It is a
// count of independent verdicts, deliberately NOT a truth value: a caller
// decides what threshold it trusts.
func Confirmations(seq uint64) (positive, rejections int) {
	for _, a := range mustGet(seq).Attestations {
		if a.Verdict == VerdictRejected {
			rejections++
		} else {
			positive++
		}
	}
	return positive, rejections
}

// ---- internal ----

func mustGet(seq uint64) *Receipt {
	assert(seq >= 1 && seq <= uint64(len(receipts)), "unknown receipt")
	return receipts[seq-1]
}

func assertVerdict(v string) {
	switch v {
	case VerdictReproduced, VerdictTestsPass, VerdictOutputMatch, VerdictPolicyOK, VerdictRejected:
		return
	}
	panic("unknown verdict: " + v)
}

func assert(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}

// Render shows the receipt log, or a single receipt at :<seq>.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	seq := parseSeq(path)
	return renderReceipt(seq)
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Agent Execution Receipts\n\n")
	sb.WriteString("_Provenance is not correctness._ Each row commits to an agent action; ")
	sb.WriteString("trust comes only from independent attestations.\n\n")
	if len(receipts) == 0 {
		sb.WriteString("_No receipts recorded yet._\n")
		return sb.String()
	}
	sb.WriteString("| # | Agent | Output commitment | Human? | ✅ | ❌ |\n")
	sb.WriteString("|---|---|---|---|---|---|\n")
	for _, r := range receipts {
		pos, rej := 0, 0
		for _, a := range r.Attestations {
			if a.Verdict == VerdictRejected {
				rej++
			} else {
				pos++
			}
		}
		human := "no"
		if r.HumanIntervened {
			human = "yes"
		}
		sb.WriteString(ufmt.Sprintf("| [%d](/r/moul/agents/receipt/v0:%d) | %s | `%s` | %s | %d | %d |\n",
			r.Seq, r.Seq, r.Agent, shortHash(r.OutputCommitment), human, pos, rej))
	}
	return sb.String()
}

func renderReceipt(seq uint64) string {
	r := mustGet(seq)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Receipt #%d\n\n", r.Seq))
	sb.WriteString(ufmt.Sprintf("- **Agent:** %s\n", r.Agent))
	sb.WriteString(ufmt.Sprintf("- **Author:** %s\n", r.Author.String()))
	sb.WriteString(ufmt.Sprintf("- **Recorded at height:** %d\n", r.Height))
	sb.WriteString(ufmt.Sprintf("- **Runtime:** %s\n", r.RuntimeID))
	sb.WriteString(ufmt.Sprintf("- **Policy version:** %s\n", r.PolicyVersion))
	sb.WriteString(ufmt.Sprintf("- **Human intervened:** %t\n\n", r.HumanIntervened))

	sb.WriteString("## Commitments\n\n")
	sb.WriteString("The realm stores only these hashes; the payloads live off-chain.\n\n")
	sb.WriteString(ufmt.Sprintf("- **Task:** `%s`\n", r.TaskHash))
	sb.WriteString(ufmt.Sprintf("- **Input:** `%s`\n", r.InputCommitment))
	sb.WriteString(ufmt.Sprintf("- **Output:** `%s`\n", r.OutputCommitment))
	sb.WriteString(ufmt.Sprintf("- **Tool-calls root:** `%s`\n\n", r.ToolCallsRoot))

	pos, rej := Confirmations(seq)
	sb.WriteString(ufmt.Sprintf("## Attestations (%d ✅ / %d ❌)\n\n", pos, rej))
	if len(r.Attestations) == 0 {
		sb.WriteString("> Unverified. This receipt proves the commitment above was made, nothing more.\n")
		return sb.String()
	}
	sb.WriteString("| Validator | Verdict | Note | Height |\n")
	sb.WriteString("|---|---|---|---|\n")
	for _, a := range r.Attestations {
		sb.WriteString(ufmt.Sprintf("| %s | %s | %s | %d |\n",
			shortHash(a.Validator.String()), a.Verdict, a.Note, a.Height))
	}
	return sb.String()
}

func parseSeq(s string) uint64 {
	var n uint64
	for i := 0; i < len(s); i++ {
		c := s[i]
		assert(c >= '0' && c <= '9', "invalid receipt path: "+s)
		n = n*10 + uint64(c-'0')
	}
	return n
}

func shortHash(s string) string {
	if len(s) <= 12 {
		return s
	}
	return s[:6] + "…" + s[len(s)-4:]
}
