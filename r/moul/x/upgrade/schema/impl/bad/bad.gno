// Package bad is the handler realm that exists to be refused (pattern G; see
// ../../README.md).
//
// It satisfies facade.Handler exactly as well as the others do: same methods,
// same signatures, compiles and proposes itself without complaint. What it does
// is drop the "upper" verb and change "repeat" to take one argument instead of
// two, both of which break a caller already compiled against v0.
//
// Nothing in gno's type system can see that. A Go interface says what methods
// exist, not which verbs the data behind them still answers, which is the whole
// argument for declaring the API as data and diffing it at accept time.
package bad

import (
	facade "gno.land/r/moul/x/upgrade/schema/facade/v0"
)

// schema drops "upper" entirely and gives "repeat" the wrong arity.
const schema = `repeat s`

type handler struct{}

func (handler) Schema() string { return schema }

func (handler) Invoke(verb string, args []string) string {
	return "this handler never gets to run"
}

// Instance exposes the singleton.
func Instance() facade.Handler { return handler{} }

// Path is this realm's own package path.
const Path = "gno.land/r/moul/x/upgrade/schema/impl/bad/v0"

func init(cur realm) {
	facade.Propose(cross(cur), Instance())
}
