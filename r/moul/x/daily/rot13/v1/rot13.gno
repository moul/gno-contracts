// Package rot13 ports Go's classic ROT13 example — the one used to teach
// strings.Map and io.Reader in the standard library docs — to an on-chain
// Gno realm. The core is a pure letter-rotation cipher over ASCII: ROT13
// shifts each letter 13 places, which (since the alphabet has 26 letters)
// makes ROT13 its own inverse. Caesar generalizes it to any shift.
//
// Everything here is pure strings/unicode logic: no state, no randomness,
// no clock — Render reads its input straight from the gnoweb path.
package rot13

import (
	"strconv"
	"strings"
)

// Rot13 applies the ROT13 substitution cipher, rotating ASCII letters by 13
// and leaving every other byte untouched. Because 13 is half of 26,
// Rot13(Rot13(s)) == s — the cipher is its own inverse. This mirrors the
// canonical strings.Map example from the Go docs.
func Rot13(s string) string {
	return strings.Map(rot13Rune, s)
}

// rot13Rune is the mapping function handed to strings.Map — the heart of the
// classic example.
func rot13Rune(r rune) rune {
	switch {
	case r >= 'a' && r <= 'z':
		return 'a' + (r-'a'+13)%26
	case r >= 'A' && r <= 'Z':
		return 'A' + (r-'A'+13)%26
	}
	return r
}

// Caesar generalizes ROT13 to an arbitrary shift. Negative and large shifts
// are normalized into [0,26). Only ASCII letters move; anything else passes
// through unchanged. Caesar(s, 13) is exactly Rot13(s).
func Caesar(s string, shift int) string {
	sh := rune(((shift % 26) + 26) % 26)
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z':
			return 'a' + (r-'a'+sh)%26
		case r >= 'A' && r <= 'Z':
			return 'A' + (r-'A'+sh)%26
		}
		return r
	}, s)
}

// hexNibble decodes a single hex digit, returning -1 if invalid.
func hexNibble(b byte) int {
	switch {
	case b >= '0' && b <= '9':
		return int(b - '0')
	case b >= 'a' && b <= 'f':
		return int(b-'a') + 10
	case b >= 'A' && b <= 'F':
		return int(b-'A') + 10
	}
	return -1
}

// percentDecode turns "%20"/"+" style path escapes back into readable text so
// gnoweb links with spaces or punctuation round-trip nicely. Invalid escapes
// are left verbatim.
func percentDecode(s string) string {
	var sb strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '+':
			sb.WriteByte(' ')
		case c == '%' && i+2 < len(s):
			hi, lo := hexNibble(s[i+1]), hexNibble(s[i+2])
			if hi >= 0 && lo >= 0 {
				sb.WriteByte(byte(hi<<4 | lo))
				i += 2
			} else {
				sb.WriteByte(c)
			}
		default:
			sb.WriteByte(c)
		}
	}
	return sb.String()
}

// Render is the gnoweb entry point (not a crossing call).
//
//	Render("")                 -> explanation + a worked example
//	Render("/Hello, Gno!")     -> the input and its ROT13
//	Render("/caesar/3/attack") -> a Caesar shift of 3 applied to "attack"
func Render(path string) string {
	p := strings.TrimPrefix(path, "/")

	// Caesar sub-path: /caesar/<shift>/<text>
	if rest, ok := strings.CutPrefix(p, "caesar/"); ok {
		shiftStr, text, found := strings.Cut(rest, "/")
		if !found {
			return renderRoot() + "\n> Usage: `/caesar/<shift>/<text>` — e.g. `/caesar/3/attack%20at%20dawn`\n"
		}
		shift, err := strconv.Atoi(shiftStr)
		if err != nil {
			return renderRoot() + "\n> `" + shiftStr + "` is not a valid integer shift.\n"
		}
		text = percentDecode(text)
		return renderCaesar(text, shift)
	}

	if p == "" {
		return renderRoot()
	}

	return renderRot13(percentDecode(p))
}

func renderRoot() string {
	var sb strings.Builder
	sb.WriteString("# ROT13\n\n")
	sb.WriteString("On-chain port of Go's classic **ROT13** cipher — the standard-library ")
	sb.WriteString("`strings.Map` / `io.Reader` teaching example. Each ASCII letter is rotated ")
	sb.WriteString("13 places through the alphabet; everything else is left alone.\n\n")
	sb.WriteString("Because the alphabet has 26 letters and 13 is exactly half, **ROT13 is its ")
	sb.WriteString("own inverse** — encoding twice returns the original text.\n\n")

	const demo = "Hello, Gno!"
	enc := Rot13(demo)
	sb.WriteString("## Example\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + demo + "` |\n")
	sb.WriteString("| ROT13 | `" + enc + "` |\n")
	sb.WriteString("| ROT13 again | `" + Rot13(enc) + "` |\n\n")

	sb.WriteString("## Try it\n\n")
	sb.WriteString("- `Render(\"/Uryyb, Tab!\")` — decode any text (append it to the path).\n")
	sb.WriteString("- `Render(\"/caesar/3/attack at dawn\")` — a general Caesar shift.\n\n")
	sb.WriteString("Or call the exported functions directly:\n\n")
	sb.WriteString("```go\n")
	sb.WriteString("Rot13(\"Hello, Gno!\")     // " + strconv.Quote(enc) + "\n")
	sb.WriteString("Caesar(\"attack\", 3)      // " + strconv.Quote(Caesar("attack", 3)) + "\n")
	sb.WriteString("Caesar(\"Hello\", 13)      // same as Rot13: " + strconv.Quote(Caesar("Hello", 13)) + "\n")
	sb.WriteString("```\n")
	return sb.String()
}

func renderRot13(text string) string {
	enc := Rot13(text)
	var sb strings.Builder
	sb.WriteString("# ROT13\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + text + "` |\n")
	sb.WriteString("| ROT13 | `" + enc + "` |\n\n")
	sb.WriteString("_ROT13 is its own inverse — running it on the output above gives back the input._\n\n")
	sb.WriteString("[Back to overview](/r/moul/x/daily/rot13/v1:)\n")
	return sb.String()
}

func renderCaesar(text string, shift int) string {
	enc := Caesar(text, shift)
	var sb strings.Builder
	sb.WriteString("# Caesar shift " + strconv.Itoa(shift) + "\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + text + "` |\n")
	sb.WriteString("| shifted | `" + enc + "` |\n\n")
	sb.WriteString("_Decode with the opposite shift: `/caesar/" + strconv.Itoa(-shift) + "/...`._\n\n")
	sb.WriteString("[Back to overview](/r/moul/x/daily/rot13/v1:)\n")
	return sb.String()
}
