// Package cowsaydemo is a small gnoweb demo of the cowsay renderer provided by
// the [p/moul/x/daily/cowsay](/p/moul/x/daily/cowsay/v1) library: it makes the
// ASCII cow say whatever you put in the path.
//
// It contains no rendering logic of its own — the art comes entirely from
// `cowsay.Say`.
package cowsaydemo

import (
	"strings"

	"gno.land/p/moul/x/daily/cowsay/v1"
)

// Render displays the cow for gnoweb.
//
//	Render("")             -> default message ("Moo!")
//	Render("/hello there") -> renders "hello there", word-wrapped
func Render(path string) string {
	msg := strings.TrimLeft(path, "/")
	art := cowsay.Say(msg)

	var b strings.Builder
	b.WriteString("# cowsay\n\n")
	if strings.TrimSpace(msg) == "" {
		b.WriteString("_Tip: pass a message in the path, e.g._ `/Hello, gno.land!`\n\n")
	}
	b.WriteString("```\n")
	b.WriteString(art)
	b.WriteString("```\n")
	return b.String()
}
