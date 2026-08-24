// Package b58demo is a small gnoweb demo of the Base58 codec provided by the
// [p/moul/x/daily/b58](/p/moul/x/daily/b58/v1) library: it renders the alphabet,
// a gallery of worked examples, and an interactive hex → Base58 round-tripper.
//
// It contains no codec logic of its own — everything comes from `b58.Encode`,
// `b58.Decode` and `b58.Alphabet`.
package b58demo

import (
	"encoding/hex"
	"strings"

	"gno.land/p/moul/x/daily/b58/v1"
)

// Render produces the gnoweb Markdown view.
//
//   - "/"        → the alphabet + a small gallery of worked examples.
//   - "/<hex>"   → decode the hex input to bytes, show its Base58, and the
//     hex-encoded decoded round-trip to prove Encode/Decode are inverse.
func Render(path string) string {
	arg := strings.TrimPrefix(path, "/")
	arg = strings.TrimSpace(arg)

	if arg == "" {
		return renderHome()
	}
	return renderHex(arg)
}

func renderHome() string {
	var sb strings.Builder
	sb.WriteString("# Base58 (Bitcoin alphabet)\n\n")
	sb.WriteString("Demo of the [`p/moul/x/daily/b58`](/p/moul/x/daily/b58/v1) library — ")
	sb.WriteString("base conversion from raw bytes (base-256) to base-58, using the ")
	sb.WriteString("Bitcoin alphabet (no `0`, `O`, `I`, `l`), pure byte-slice math, no `math/big`.\n\n")

	sb.WriteString("## Alphabet\n\n")
	sb.WriteString("```\n")
	sb.WriteString(b58.Alphabet)
	sb.WriteString("\n```\n\n")
	sb.WriteString("58 characters, index 0…57.\n\n")

	sb.WriteString("## Examples\n\n")
	sb.WriteString("| input (utf-8) | hex | Base58 |\n")
	sb.WriteString("|---|---|---|\n")
	examples := []string{"", "hello world", "gno.land", "Bitcoin"}
	for _, e := range examples {
		h := hex.EncodeToString([]byte(e))
		if h == "" {
			h = "(empty)"
		}
		label := e
		if label == "" {
			label = "(empty)"
		}
		sb.WriteString("| `" + label + "` | `" + h + "` | `" + b58.Encode([]byte(e)) + "` |\n")
	}
	sb.WriteString("\n")

	sb.WriteString("Leading zero bytes → leading `1`s:\n\n")
	sb.WriteString("| bytes | Base58 |\n|---|---|\n")
	sb.WriteString("| `[0x00]` | `" + b58.Encode([]byte{0}) + "` |\n")
	sb.WriteString("| `[0x00 0x00 0x00]` | `" + b58.Encode([]byte{0, 0, 0}) + "` |\n\n")

	sb.WriteString("## Try it\n\n")
	sb.WriteString("Append a hex string to the path to encode/round-trip it:\n\n")
	sb.WriteString("- `/68656c6c6f` — the bytes for \"hello\"\n")
	sb.WriteString("- `/00000000` — four zero bytes\n")
	sb.WriteString("- `/deadbeef`\n")
	return sb.String()
}

func renderHex(arg string) string {
	var sb strings.Builder
	sb.WriteString("# Base58 — round-trip\n\n")
	sb.WriteString("[← alphabet & examples](/r/moul/x/daily/b58demo/v1)\n\n")

	raw, err := hex.DecodeString(arg)
	if err != nil {
		sb.WriteString("**Invalid hex input.**\n\n")
		sb.WriteString("`" + arg + "` is not a valid hex string. ")
		sb.WriteString("Provide an even number of hex digits, e.g. `/deadbeef`.\n")
		return sb.String()
	}

	encoded := b58.Encode(raw)
	decoded := b58.Decode(encoded)
	roundTrip := hex.EncodeToString(decoded)

	inHex := arg
	if inHex == "" {
		inHex = "(empty)"
	}
	outHex := roundTrip
	if outHex == "" {
		outHex = "(empty)"
	}
	enc := encoded
	if enc == "" {
		enc = "(empty)"
	}

	sb.WriteString("| step | value |\n|---|---|\n")
	sb.WriteString("| hex input | `" + inHex + "` |\n")
	sb.WriteString("| bytes | `" + byteList(raw) + "` |\n")
	sb.WriteString("| **Base58** | `" + enc + "` |\n")
	sb.WriteString("| decoded (hex) | `" + outHex + "` |\n\n")

	if roundTrip == arg {
		sb.WriteString("✓ Round-trip matches: `Decode(Encode(x)) == x`.\n")
	} else {
		sb.WriteString("✗ Round-trip mismatch.\n")
	}
	return sb.String()
}

// byteList renders a byte slice as a compact space-separated hex list.
func byteList(b []byte) string {
	if len(b) == 0 {
		return "(none)"
	}
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(b)*3)
	for i, c := range b {
		if i > 0 {
			out = append(out, ' ')
		}
		out = append(out, digits[c>>4], digits[c&0x0f])
	}
	return string(out)
}
