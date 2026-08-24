// Package piglatindemo is a small gnoweb demo of the Pig Latin translator
// provided by the [p/moul/x/daily/piglatin](/p/moul/x/daily/piglatin/v1)
// library: it renders the rules, a gallery of worked examples, and an
// interactive sentence translator.
//
// It contains no translation logic of its own — everything comes from
// `piglatin.Translate` and `piglatin.TranslateToken`.
package piglatindemo

import (
	"strings"

	"gno.land/p/moul/x/daily/piglatin/v1"
)

// Render is the gnoweb entrypoint (Markdown). Root explains the rules; any
// other path is treated as a sentence to translate, e.g. Render("/Hello world").
func Render(path string) string {
	var b strings.Builder

	sentence := strings.TrimPrefix(path, "/")
	sentence = strings.TrimSpace(sentence)

	if sentence == "" {
		b.WriteString("# Pig Latin\n\n")
		b.WriteString("Demo of the [`p/moul/x/daily/piglatin`](/p/moul/x/daily/piglatin/v1) ")
		b.WriteString("library — a tiny port of the classic **Pig Latin** translator ")
		b.WriteString("(the go-to beginner exercise). Pure `strings`/`unicode`, fully deterministic.\n\n")
		b.WriteString("## Rules\n\n")
		b.WriteString("1. Word starts with a **vowel** → append `way`. `apple` → `appleway`\n")
		b.WriteString("2. Word starts with **consonant(s)** → move the leading consonant cluster to the end, then add `ay`. `string` → `ingstray`\n")
		b.WriteString("3. `y` is a consonant only as the first letter (`yellow` → `ellowyay`); otherwise a vowel (`myth` → `ythmay`).\n")
		b.WriteString("4. **Capitalization** is preserved: `Hello` → `Ellohay`, `NASA` → `ASANAY`.\n")
		b.WriteString("5. **Punctuation** glued to a word stays put: `Hello,` → `Ellohay,`.\n\n")
		b.WriteString("## Try it\n\n")
		b.WriteString("Append a sentence to the path — spaces are fine:\n\n")
		for _, ex := range []string{"hello world", "The quick brown fox", "I love Gno!"} {
			b.WriteString("- [`/")
			b.WriteString(ex)
			b.WriteString("`](/r/moul/x/daily/piglatindemo/v1:/")
			b.WriteString(ex)
			b.WriteString(") → `")
			b.WriteString(piglatin.Translate(ex))
			b.WriteString("`\n")
		}
		b.WriteString("\n## Examples\n\n")
		b.WriteString("| Input | Pig Latin |\n|---|---|\n")
		for _, w := range []string{"pig", "banana", "smile", "eat", "yellow", "myth", "Hello,", "GNO"} {
			b.WriteString("| `")
			b.WriteString(w)
			b.WriteString("` | `")
			b.WriteString(piglatin.TranslateToken(w))
			b.WriteString("` |\n")
		}
		return b.String()
	}

	b.WriteString("# Pig Latin\n\n")
	b.WriteString("**Original:**\n\n> ")
	b.WriteString(sentence)
	b.WriteString("\n\n**Pig Latin:**\n\n> ")
	b.WriteString(piglatin.Translate(sentence))
	b.WriteString("\n\n---\n\n[← rules & examples](/r/moul/x/daily/piglatindemo/v1)\n")
	return b.String()
}
