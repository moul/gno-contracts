package impl

import (
	"testing"

	facade "gno.land/r/moul/x/upgrade/schema/facade/v0"
	bad "gno.land/r/moul/x/upgrade/schema/impl/bad/v0"
	implv0 "gno.land/r/moul/x/upgrade/schema/impl/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestGrowTheAPI is the whole pattern: three handlers propose themselves, the
// API is enumerable without a transaction, it grows without a new signature at
// the permanent path, and the one candidate that would break a caller is
// refused despite satisfying the interface.
func TestGrowTheAPI(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(facade.Ownable.Owner()))
	uassert.Equal(t, 3, len(facade.Candidates()), "all three handlers nominated themselves")

	// v0: two verbs, and a caller can discover them with no transaction.
	facade.Accept(cross(cur), implv0.Path)
	uassert.Equal(t, "upper, repeat", joinVerbs(facade.Verbs()))
	uassert.Equal(t, "repeat(s, n)", facade.Signature("repeat"))
	uassert.Equal(t, "GNO", facade.Call(cross(cur), "upper", "gno"))
	uassert.Equal(t, "abab", facade.Call(cross(cur), "repeat", "ab|2"))

	// The facade checks arity before the handler runs, so the message names the
	// signature rather than whatever the handler would have done.
	uassert.AbortsContains(t, cur, "verb repeat takes 2 argument(s), got 1, signature is repeat(s, n)", func() {
		facade.Call(cross(cur), "repeat", "ab")
	})
	uassert.AbortsContains(t, cur, "unknown verb nope, known: upper, repeat", func() {
		facade.Call(cross(cur), "nope", "")
	})

	// v1 ADDS a verb and keeps the other two, so it is accepted. No new realm,
	// no new signature at the permanent path, and old callers are untouched.
	facade.Accept(cross(cur), Path)
	uassert.Equal(t, "upper, repeat, surround", joinVerbs(facade.Verbs()))
	uassert.Equal(t, "[gno]", facade.Call(cross(cur), "surround", "gno|[|]"))
	uassert.Equal(t, "GNO", facade.Call(cross(cur), "upper", "gno"), "v0's verbs still answer")

	// The refusal. bad satisfies Handler exactly as well as the others do; what
	// it does is drop a verb and reshape another, which only the schema sees.
	uassert.AbortsContains(t, cur, "schema regression: the candidate drops verb upper", func() {
		facade.Accept(cross(cur), bad.Path)
	})
	uassert.Equal(t, Path, facade.Live(), "a refused accept changes nothing")

	// The diff is SYMMETRIC, which the first draft of this test got wrong: now
	// that v1 has added a verb, rolling back to v0 DROPS it and is a regression
	// by the same rule. Accept refuses the rollback.
	uassert.AbortsContains(t, cur, "schema regression: the candidate drops verb surround", func() {
		facade.Accept(cross(cur), implv0.Path)
	})
	uassert.Equal(t, Path, facade.Live())

	// Which is why the override exists. A pattern that can only move forward is
	// worse than one with no diff at all.
	facade.AcceptBreaking(cross(cur), implv0.Path)
	uassert.Equal(t, "upper, repeat", joinVerbs(facade.Verbs()))
	facade.Accept(cross(cur), Path)

	uassert.Equal(t, "upper s\nrepeat s n\nsurround s left right\n", facade.SchemaText())
	uassert.Equal(t, "schema/facade/v0: gno.land/r/moul/x/upgrade/schema/impl/v1\n"+
		"- upper(s)\n- repeat(s, n)\n- surround(s, left, right)\n", facade.Render(""))
}

// TestDispatchCost100 does 100 dispatches through this pattern's entry point,
// so `gno test -print-runtime-metrics` prints a cycle count for a known
// workload. Its twin is TestDispatchCost100 in adminreg/impl/gen1.
//
// It measures what a call costs through each pattern AS SHIPPED, which is the
// number that decides between them. It is NOT the cost of the string boundary
// in isolation: this path also crosses a realm and the typed one does not.
func TestDispatchCost100(cur realm, t *testing.T) {
	// Runs after TestGrowTheAPI, so v1 is already live. Accepting anything here
	// would fight that test's state, and the verb costs the same either way.
	for i := 0; i < 100; i++ {
		facade.Call(cross(cur), "upper", "gno")
	}
	uassert.Equal(t, "GNO", facade.Call(cross(cur), "upper", "gno"))
}

// TestMalformedSchemaIsRejectedAtProposal checks the other validation edge: a
// schema that cannot be parsed never becomes a candidate.
func TestMalformedSchemaIsRejectedAtProposal(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "malformed schema", func() {
		facade.Propose(cross(cur), badSchema{})
	})
}

type badSchema struct{}

func (badSchema) Schema() string                         { return "Upper s" } // capital, not [a-z0-9_]
func (badSchema) Invoke(string, []string) string         { return "" }

func joinVerbs(v []string) string {
	out := ""
	for i, s := range v {
		if i > 0 {
			out += ", "
		}
		out += s
	}
	return out
}
