// Package rot13demo is a small gnoweb demo of the ROT13 / Caesar cipher
// provided by the [p/moul/x/daily/rot13](/p/moul/x/daily/rot13/v1) library: it
// renders an explanation, a worked ROT13 example, and interactive path-driven
// ROT13 and Caesar transforms.
//
// It contains no cipher logic of its own — everything comes from `rot13.Rot13`
// and `rot13.Caesar`. Render reads its input straight from the gnoweb path.
package rot13demo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/rot13/v1"
)

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
	sb.WriteString("Demo of the [`p/moul/x/daily/rot13`](/p/moul/x/daily/rot13/v1) library — ")
	sb.WriteString("an on-chain port of Go's classic **ROT13** cipher, the standard-library ")
	sb.WriteString("`strings.Map` / `io.Reader` teaching example. Each ASCII letter is rotated ")
	sb.WriteString("13 places through the alphabet; everything else is left alone.\n\n")
	sb.WriteString("Because the alphabet has 26 letters and 13 is exactly half, **ROT13 is its ")
	sb.WriteString("own inverse** — encoding twice returns the original text.\n\n")

	const demo = "Hello, Gno!"
	enc := rot13.Rot13(demo)
	sb.WriteString("## Example\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + demo + "` |\n")
	sb.WriteString("| ROT13 | `" + enc + "` |\n")
	sb.WriteString("| ROT13 again | `" + rot13.Rot13(enc) + "` |\n\n")

	sb.WriteString("## Try it\n\n")
	sb.WriteString("- `Render(\"/Uryyb, Tab!\")` — decode any text (append it to the path).\n")
	sb.WriteString("- `Render(\"/caesar/3/attack at dawn\")` — a general Caesar shift.\n\n")
	sb.WriteString("Or call the library functions directly:\n\n")
	sb.WriteString("```go\n")
	sb.WriteString("rot13.Rot13(\"Hello, Gno!\")     // " + strconv.Quote(enc) + "\n")
	sb.WriteString("rot13.Caesar(\"attack\", 3)      // " + strconv.Quote(rot13.Caesar("attack", 3)) + "\n")
	sb.WriteString("rot13.Caesar(\"Hello\", 13)      // same as Rot13: " + strconv.Quote(rot13.Caesar("Hello", 13)) + "\n")
	sb.WriteString("```\n")
	return sb.String()
}

func renderRot13(text string) string {
	enc := rot13.Rot13(text)
	var sb strings.Builder
	sb.WriteString("# ROT13\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + text + "` |\n")
	sb.WriteString("| ROT13 | `" + enc + "` |\n\n")
	sb.WriteString("_ROT13 is its own inverse — running it on the output above gives back the input._\n\n")
	sb.WriteString("[Back to overview](/r/moul/x/daily/rot13demo/v1:)\n")
	return sb.String()
}

func renderCaesar(text string, shift int) string {
	enc := rot13.Caesar(text, shift)
	var sb strings.Builder
	sb.WriteString("# Caesar shift " + strconv.Itoa(shift) + "\n\n")
	sb.WriteString("| stage | text |\n|---|---|\n")
	sb.WriteString("| input | `" + text + "` |\n")
	sb.WriteString("| shifted | `" + enc + "` |\n\n")
	sb.WriteString("_Decode with the opposite shift: `/caesar/" + strconv.Itoa(-shift) + "/...`._\n\n")
	sb.WriteString("[Back to overview](/r/moul/x/daily/rot13demo/v1:)\n")
	return sb.String()
}
