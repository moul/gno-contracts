// untrusted-render: every string Render echoes is either a verb name validated
// by parseSchema against [a-z0-9_] at accept time, or a package path read off a
// crossing frame. No caller-typed payload is ever rendered.
//
// Package facade is the permanent entry point of the "API as data" upgrade
// pattern (pattern G of the exploration; see ../../README.md).
//
// Patterns E and F put a Go interface at the permanent path, which fixes the
// method set at deploy: adding an operation later needs a whole extra realm.
// This one puts a single entry point there instead,
//
//	Call(cur realm, verb, payload string) string
//
// and moves the API into DATA that each implementation declares. The signature
// that can never change is that one line; everything the application does can
// still grow.
//
// Three things fall out of the API being data, and they are the reason to pay
// the price below:
//
//  1. Callers can ENUMERATE it. Verbs, Signature and SchemaText answer without
//     a transaction, so a client discovers the API instead of being compiled
//     against it.
//  2. Payloads are CHECKED before the handler runs, so an arity mistake is one
//     abort with a readable message rather than whatever the handler does with
//     the wrong number of arguments.
//  3. Upgrades can be DIFFED. Accept refuses a handler whose schema would drop
//     or reshape a verb some existing caller depends on, which no amount of Go
//     interface satisfaction can catch: a handler is free to satisfy Handler
//     and answer nothing.
//
// The price is the type system. Arguments are strings a caller encodes, and a
// misspelled verb is an abort at runtime rather than a compile error. Pattern F
// is the other side of that trade and both ship here on purpose.
//
// State is deliberately out of scope. These handlers are pure; where an
// application's data should live is pattern C's question, and the answer does
// not change because the entry point became a string.
package facade

import (
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const owner address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

const prefix = "gno.land/r/moul/x/upgrade/schema/impl/"

// sep is the payload separator. A single byte, because the point here is the
// shape of the boundary and not the encoding: a real one would need escaping,
// and choosing it is a decision this pattern does not make for you.
const sep = "|"

// Handler is the whole interface an implementation satisfies. It never changes,
// because everything that would have changed it is in Schema instead.
type Handler interface {
	// Schema declares the API, one verb per line, "name arg1 arg2".
	Schema() string
	// Invoke runs a verb. The facade has already checked that the verb exists
	// and that args has exactly the declared arity.
	Invoke(verb string, args []string) string
}

type verb struct {
	name   string
	params []string
}

var (
	Ownable = ownable.NewWithAddress(owner)

	candidates = avl.NewTree() // pkgpath -> Handler
	live       Handler
	livePath   string
	liveVerbs  = avl.NewTree() // verb name -> *verb, for lookup
	liveOrder  []string        // the same verbs in DECLARATION order, for listing
)

// Propose nominates the calling realm, exactly as in pattern F. Its schema is
// parsed here so a malformed one is rejected at proposal rather than at accept.
func Propose(cur realm, h Handler) {
	caller := cur.Previous().PkgPath()
	if !strings.HasPrefix(caller, prefix) {
		panic("unauthorized: " + caller + " is not under " + prefix)
	}
	if h == nil {
		panic("handler must not be nil")
	}
	parseSchema(h.Schema()) // panics if malformed
	candidates.Set(caller, h)
}

// Accept promotes a candidate, and refuses one that would break an existing
// caller. This is the check a Go interface cannot express.
func Accept(cur realm, pkgPath string) {
	h, next, order := resolve(cur, pkgPath)
	assertNoRegression(next)
	live, livePath, liveVerbs, liveOrder = h, pkgPath, next, order
}

// AcceptBreaking promotes a candidate that Accept refuses.
//
// It exists because the diff is SYMMETRIC, which is not obvious until it bites:
// once v1 has added a verb, rolling back to v0 drops that verb and is a
// regression by exactly the same rule that protects callers going forward. A
// pattern that can only move forward is worse than one with no diff at all, so
// the escape hatch is required, and making it a separate function is the point:
// the owner has to type a different word, and the audit log shows which one.
//
// Use it to roll back, and to retire a verb nobody calls any more. Not to make
// an upgrade go through.
func AcceptBreaking(cur realm, pkgPath string) {
	h, next, order := resolve(cur, pkgPath)
	live, livePath, liveVerbs, liveOrder = h, pkgPath, next, order
}

// resolve is the owner check and the lookup both accepts share.
func resolve(cur realm, pkgPath string) (Handler, *avl.Tree, []string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	v := candidates.Get(pkgPath)
	if v == nil {
		panic("no candidate at " + pkgPath)
	}
	h := v.(Handler)
	t, order := parseSchema(h.Schema())
	return h, t, order
}

// assertNoRegression is the upgrade diff. A new schema may ADD verbs and may not
// remove one or change its arity, because a caller compiled against the old one
// is still out there calling it.
func assertNoRegression(next *avl.Tree) {
	// Walk in DECLARATION order, not avl order, so the verb named in the abort
	// is the first one a reader of the live schema would reach. Iterating the
	// tree reports whichever violation happens to sort first, which makes the
	// message depend on a verb's spelling.
	for _, name := range liveOrder {
		old := liveVerbs.Get(name).(*verb)
		n := next.Get(name)
		if n == nil {
			panic("schema regression: the candidate drops verb " + name + ", which an existing caller may still call; AcceptBreaking overrides")
		}
		if len(n.(*verb).params) != len(old.params) {
			panic("schema regression: the candidate changes the arity of verb " + name + "; AcceptBreaking overrides")
		}
	}
}

// Call is the one signature this realm is committed to forever.
func Call(cur realm, verbName, payload string) string {
	assertLive()
	v := liveVerbs.Get(verbName)
	if v == nil {
		panic("unknown verb " + verbName + ", known: " + strings.Join(Verbs(), ", "))
	}
	spec := v.(*verb)
	args := []string{}
	if payload != "" {
		args = strings.Split(payload, sep)
	}
	if len(args) != len(spec.params) {
		panic(ufmt.Sprintf("verb %s takes %d argument(s), got %d, signature is %s",
			verbName, len(spec.params), len(args), Signature(verbName)))
	}
	return live.Invoke(verbName, args)
}

// Verbs lists the accepted API in DECLARATION order, which is the order the
// handler wrote it in and the order a reader of the schema expects. Iterating
// the avl tree instead would list them alphabetically, silently: caught by a
// test, not by a compiler.
func Verbs() []string {
	return liveOrder
}

// Signature is one verb's shape, as a caller would write it.
func Signature(name string) string {
	v := liveVerbs.Get(name)
	if v == nil {
		return ""
	}
	return name + "(" + strings.Join(v.(*verb).params, ", ") + ")"
}

// SchemaText is the whole accepted API in the declaration format, so a client
// can read back exactly what the handler declared.
func SchemaText() string {
	out := ""
	for _, n := range Verbs() {
		v := liveVerbs.Get(n).(*verb)
		out += n
		for _, p := range v.params {
			out += " " + p
		}
		out += "\n"
	}
	return out
}

// Live is the package path currently serving, or "" before the first Accept.
func Live() string {
	return livePath
}

// Candidates lists every path that has nominated itself, in order.
func Candidates() []string {
	out := []string{}
	candidates.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

func assertLive() {
	if live == nil {
		panic("no handler accepted")
	}
}

// parseSchema turns the declaration text into verbs, and is the only validation
// of a name that Render later echoes.
func parseSchema(text string) (*avl.Tree, []string) {
	t := avl.NewTree()
	order := []string{}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Split(line, " ")
		name := fields[0]
		assertIdent(name)
		params := []string{}
		for _, f := range fields[1:] {
			if f == "" {
				continue
			}
			assertIdent(f)
			params = append(params, f)
		}
		if t.Get(name) != nil {
			panic("malformed schema: verb " + name + " declared twice")
		}
		t.Set(name, &verb{name: name, params: params})
		order = append(order, name)
	}
	if t.Size() == 0 {
		panic("malformed schema: no verbs declared")
	}
	return t, order
}

func assertIdent(s string) {
	if s == "" {
		panic("malformed schema: empty name")
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_' {
			panic("malformed schema: " + s + " is not [a-z0-9_]")
		}
	}
}

func Render(_ string) string {
	if live == nil {
		return ufmt.Sprintf("schema/facade/v0: no handler accepted (%d candidate(s))\n", candidates.Size())
	}
	out := ufmt.Sprintf("schema/facade/v0: %s\n", livePath)
	for _, n := range Verbs() {
		out += "- " + Signature(n) + "\n"
	}
	return out
}
