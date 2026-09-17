package receipt

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	agentKey = testutils.TestAddress("agent")
	val1     = testutils.TestAddress("validator1")
	val2     = testutils.TestAddress("validator2")
)

func TestRecordAndAttest(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(agentKey))
	seq := Record(cross(cur), "percy", "task#1", "in#1", "out#1", "claude-opus-4-8", "policy-v1", "tools#1", false)
	uassert.Equal(t, uint64(1), seq)
	uassert.Equal(t, 1, Count())

	// Fresh receipt is unverified: no attestations.
	pos, rej := Confirmations(seq)
	uassert.Equal(t, 0, pos)
	uassert.Equal(t, 0, rej)

	// Two independent validators attest.
	testing.SetRealm(testing.NewUserRealm(val1))
	Attest(cross(cur), seq, VerdictReproduced, "re-ran, matched")
	testing.SetRealm(testing.NewUserRealm(val2))
	Attest(cross(cur), seq, VerdictTestsPass, "suite green")

	pos, rej = Confirmations(seq)
	uassert.Equal(t, 2, pos)
	uassert.Equal(t, 0, rej)

	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("1")) > 0)
}

func TestNoSelfAttest(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(agentKey))
	seq := Record(cross(cur), "percy", "task#2", "in#2", "out#2", "rt", "p", "tr", false)

	// The author cannot attest to their own receipt.
	uassert.AbortsWithMessage(t, cur, "author cannot attest to their own receipt", func(cur realm) {
		Attest(cur, seq, VerdictReproduced, "trust me")
	})
}

func TestNoDoubleAttest(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(agentKey))
	seq := Record(cross(cur), "percy", "task#3", "in#3", "out#3", "rt", "p", "tr", false)

	testing.SetRealm(testing.NewUserRealm(val1))
	Attest(cross(cur), seq, VerdictOutputMatch, "ok")
	uassert.AbortsWithMessage(t, cur, "validator already attested", func(cur realm) {
		Attest(cur, seq, VerdictRejected, "changed my mind")
	})
}

func TestBadVerdict(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(agentKey))
	seq := Record(cross(cur), "percy", "task#4", "in#4", "out#4", "rt", "p", "tr", false)
	testing.SetRealm(testing.NewUserRealm(val1))
	uassert.AbortsWithMessage(t, cur, "unknown verdict: maybe", func(cur realm) {
		Attest(cur, seq, "maybe", "")
	})
}
