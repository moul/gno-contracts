// Package impl is version 1 of the implementation realm of the
// "self-registering implementation" upgrade pattern (pattern E; see
// ../../README.md).
//
// Identical wiring to v0, different behaviour. Deploying it takes the facade
// over on the spot, with no transaction from anybody.
package impl

import (
	facade "gno.land/r/moul/x/upgrade/selfreg/facade/v0"
)

type greeter struct{}

func (greeter) Greet(name string) string { return "HELLO, " + name + "!" }
func (greeter) Version() string          { return "impl/v1" }

// Instance exposes the singleton so a test (or a rollback) can re-register it
// without redeploying.
func Instance() facade.Impl { return greeter{} }

func init(cur realm) {
	facade.Register(cross(cur), Instance())
}

// Register re-registers this implementation with the facade. init does it once
// at deploy; exposing it as a transaction is what makes a rollback to an
// already-deployed version a single call.
func Register(cur realm) {
	facade.Register(cross(cur), Instance())
}
