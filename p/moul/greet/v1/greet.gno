// Package greet is a tiny pure package used as a canary: it proves that
// versioned cross-package resolution (gno.land/p/moul/greet/v1) works in the
// workspace and in CI. Replace or remove it once real packages land.
package greet

import "strings"

// Greet returns a friendly greeting for name (defaults to "world").
func Greet(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		name = "world"
	}
	return "Hello, " + name + "!"
}
