// Package impl is version 0 of the handler realm of the "API as data" upgrade
// pattern (pattern G; see ../../README.md).
//
// Two verbs, declared as text rather than as a method set. Deploying nominates
// it; the facade owner accepts it by path.
package impl

import (
	"strings"

	facade "gno.land/r/moul/x/upgrade/schema/facade/v0"
)

// schema is this version's whole API. One verb per line, name then parameters.
const schema = `upper s
repeat s n`

type handler struct{}

func (handler) Schema() string { return schema }

func (handler) Invoke(verb string, args []string) string {
	switch verb {
	case "upper":
		return strings.ToUpper(args[0])
	case "repeat":
		return strings.Repeat(args[0], atoi(args[1]))
	}
	// Unreachable: the facade checked the verb against this schema first.
	panic("unknown verb " + verb)
}

// atoi is hand-rolled to keep the failure message about the ARGUMENT rather
// than about strconv, which is the whole difference a typed boundary would have
// made here.
func atoi(s string) int {
	if s == "" {
		panic("expected a number, got an empty argument")
	}
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			panic("expected a number, got " + s)
		}
		n = n*10 + int(c-'0')
		if n > 64 {
			panic("refusing to repeat more than 64 times")
		}
	}
	return n
}

// Instance exposes the singleton.
func Instance() facade.Handler { return handler{} }

// Path is this realm's own package path, the string the facade owner accepts.
const Path = "gno.land/r/moul/x/upgrade/schema/impl/v0"

func init(cur realm) {
	facade.Propose(cross(cur), Instance())
}

// Propose re-nominates this handler, so a rollback needs no redeploy.
func Propose(cur realm) {
	facade.Propose(cross(cur), Instance())
}
