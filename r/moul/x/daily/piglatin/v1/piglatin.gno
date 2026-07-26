// Package piglatin ports the classic "Pig Latin" translator — a staple Go
// beginner exercise — to an on-chain gno.land realm.
//
// Rules implemented (the standard English game):
//   - A word that starts with a vowel gets "way" appended:   "apple" -> "appleway"
//   - A word that starts with one or more consonants has that leading
//     consonant cluster moved to the end, followed by "ay":  "string" -> "ingstray"
//   - "y" acts as a consonant only when it is the first letter of the word
//     ("yellow" -> "ellowyay"); elsewhere it counts as a vowel ("myth" -> "ythmay").
//   - Original capitalization of the word is preserved (title-case in, title-case
//     out): "Hello" -> "Ellohay".
//   - Trailing/leading punctuation attached to a word is preserved in place:
//     "Hello," -> "Ellohay,".
//
// Everything is pure strings/unicode — deterministic and reproducible on-chain.
package piglatin

import (
	"strings"
	"unicode"
)

const suffixVowel = "way"
const suffixConsonant = "ay"

func isVowel(r rune) bool {
	switch unicode.ToLower(r) {
	case 'a', 'e', 'i', 'o', 'u':
		return true
	}
	return false
}

// isLetter reports whether r is an ASCII/unicode letter (word character).
func isLetter(r rune) bool {
	return unicode.IsLetter(r)
}

// translateWord converts a single "core" alphabetic word (no surrounding
// punctuation) to Pig Latin, preserving its capitalization pattern.
func translateWord(word string) string {
	if word == "" {
		return word
	}
	runes := []rune(word)

	// Find the leading consonant cluster. 'y' is a consonant only in position 0.
	start := 0
	for i, r := range runes {
		if isVowel(r) {
			break
		}
		// 'y' after the first letter behaves like a vowel: stop the cluster.
		if i > 0 && unicode.ToLower(r) == 'y' {
			break
		}
		start = i + 1
	}

	var out []rune
	if start == 0 {
		// Starts with a vowel.
		out = append(out, runes...)
		out = append(out, []rune(suffixVowel)...)
	} else if start >= len(runes) {
		// All consonants (no vowel found), e.g. "shh" — just append "ay".
		out = append(out, runes...)
		out = append(out, []rune(suffixConsonant)...)
	} else {
		out = append(out, runes[start:]...)
		out = append(out, runes[:start]...)
		out = append(out, []rune(suffixConsonant)...)
	}

	return applyCase(word, string(out))
}

// applyCase re-applies the capitalization shape of the original word to the
// translated word. Two common shapes are handled: ALL CAPS and Title-case;
// everything else is returned lowercase.
func applyCase(orig, translated string) string {
	origRunes := []rune(orig)
	if len(origRunes) == 0 {
		return translated
	}

	// Count letters and uppercase letters in the original.
	letters, uppers := 0, 0
	for _, r := range origRunes {
		if unicode.IsLetter(r) {
			letters++
			if unicode.IsUpper(r) {
				uppers++
			}
		}
	}

	low := strings.ToLower(translated)
	switch {
	case letters > 0 && uppers == letters && letters > 1:
		// ALL CAPS -> keep upper.
		return strings.ToUpper(low)
	case unicode.IsUpper(origRunes[0]):
		// Title-case -> capitalize first letter of the result.
		tr := []rune(low)
		if len(tr) > 0 {
			tr[0] = unicode.ToUpper(tr[0])
		}
		return string(tr)
	default:
		return low
	}
}

// splitAffixes separates a token into (leading punctuation, core word,
// trailing punctuation) where the core is the contiguous run of letters
// (apostrophes inside are kept as part of the core, e.g. "don't").
func splitAffixes(token string) (string, string, string) {
	runes := []rune(token)
	i := 0
	for i < len(runes) && !isLetter(runes[i]) {
		i++
	}
	j := len(runes)
	for j > i && !isLetter(runes[j-1]) {
		j--
	}
	if i >= j {
		return token, "", "" // no letters at all
	}
	return string(runes[:i]), string(runes[i:j]), string(runes[j:])
}

// TranslateToken translates a single whitespace-delimited token, preserving
// any punctuation glued to its edges.
func TranslateToken(token string) string {
	lead, core, trail := splitAffixes(token)
	if core == "" {
		return token
	}
	return lead + translateWord(core) + trail
}

// Translate applies Pig Latin to every word in the sentence while preserving
// the original whitespace between words.
func Translate(sentence string) string {
	var b strings.Builder
	var word strings.Builder
	flush := func() {
		if word.Len() > 0 {
			b.WriteString(TranslateToken(word.String()))
			word.Reset()
		}
	}
	for _, r := range sentence {
		if unicode.IsSpace(r) {
			flush()
			b.WriteRune(r)
			continue
		}
		word.WriteRune(r)
	}
	flush()
	return b.String()
}

// Render is the gnoweb entrypoint (Markdown). Root explains the rules; any
// other path is treated as a sentence to translate, e.g. Render("/Hello world").
func Render(path string) string {
	var b strings.Builder

	sentence := strings.TrimPrefix(path, "/")
	sentence = strings.TrimSpace(sentence)

	if sentence == "" {
		b.WriteString("# Pig Latin\n\n")
		b.WriteString("A tiny on-chain port of the classic **Pig Latin** translator ")
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
			b.WriteString("`](/r/moul/x/daily/piglatin/v1:/")
			b.WriteString(ex)
			b.WriteString(") → `")
			b.WriteString(Translate(ex))
			b.WriteString("`\n")
		}
		b.WriteString("\n## Examples\n\n")
		b.WriteString("| Input | Pig Latin |\n|---|---|\n")
		for _, w := range []string{"pig", "banana", "smile", "eat", "yellow", "myth", "Hello,", "GNO"} {
			b.WriteString("| `")
			b.WriteString(w)
			b.WriteString("` | `")
			b.WriteString(Translate(w))
			b.WriteString("` |\n")
		}
		return b.String()
	}

	b.WriteString("# Pig Latin\n\n")
	b.WriteString("**Original:**\n\n> ")
	b.WriteString(sentence)
	b.WriteString("\n\n**Pig Latin:**\n\n> ")
	b.WriteString(Translate(sentence))
	b.WriteString("\n\n---\n\n[← rules & examples](/r/moul/x/daily/piglatin/v1)\n")
	return b.String()
}
