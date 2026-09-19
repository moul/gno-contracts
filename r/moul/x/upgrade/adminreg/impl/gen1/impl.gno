// Package impl is version 1 of the implementation realm of the "propose and
// accept" upgrade pattern (pattern F; see ../../README.md).
//
// Deploying it only nominates it. It serves nothing until the facade owner
// accepts this path.
package impl

import (
	facade "gno.land/r/moul/x/upgrade/adminreg/facade/v0"
)

type greeter struct{}

func (greeter) Greet(name string) string { return "HELLO, " + name + "!" }
func (greeter) Version() string          { return "impl/v1" }

// Instance exposes the singleton.
func Instance() facade.Impl { return greeter{} }

func init(cur realm) {
	facade.Propose(cross(cur), Instance())
}

// Propose re-nominates this implementation. init does it at deploy; exposing it
// as a transaction lets a candidate be restored without redeploying.
func Propose(cur realm) {
	facade.Propose(cross(cur), Instance())
}

// Path is this realm's own package path, the string the facade owner accepts.
const Path = "gno.land/r/moul/x/upgrade/adminreg/impl/v1"
