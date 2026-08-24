// Package cowsay is an on-chain Gno port of the classic `cowsay` program:
// it builds an ASCII cow with a speech bubble containing a message — as a
// reusable pure package.
//
// Original: cowsay by Tony Monroe (1999), a Perl program later ported to Go
// many times. This package reimplements the core rendering — bubble framing,
// word-wrapping and the cow art — as pure, deterministic string logic.
//
// A live demo of this package (an interactive cow that says whatever you put in
// the path) is at [r/moul/x/daily/cowsaydemo](/r/moul/x/daily/cowsaydemo/v1).
package cowsay

import (
	"strings"
)

// defaultMessage is shown when no message is supplied.
const defaultMessage = "Moo!"

// wrapWidth is the maximum bubble text width (classic cowsay uses 40).
const wrapWidth = 40

// Say returns the full cowsay art (speech bubble + cow) for msg.
// An empty msg falls back to the default message.
func Say(msg string) string {
	msg = strings.TrimSpace(msg)
	if msg == "" {
		msg = defaultMessage
	}
	lines := wrap(msg, wrapWidth)
	return balloon(lines) + cow
}

// balloon builds the speech bubble around the given (already wrapped) lines.
func balloon(lines []string) string {
	width := maxLen(lines)

	var b strings.Builder
	// top border: " " + "_"*(width+2)
	b.WriteString(" ")
	b.WriteString(strings.Repeat("_", width+2))
	b.WriteString("\n")

	n := len(lines)
	for i, ln := range lines {
		left, right := borderChars(i, n)
		b.WriteString(left)
		b.WriteString(" ")
		b.WriteString(ln)
		b.WriteString(strings.Repeat(" ", width-len(ln)))
		b.WriteString(" ")
		b.WriteString(right)
		b.WriteString("\n")
	}

	// bottom border: " " + "-"*(width+2)
	b.WriteString(" ")
	b.WriteString(strings.Repeat("-", width+2))
	b.WriteString("\n")
	return b.String()
}

// borderChars picks the left/right bubble characters for line i of n.
// Single line uses < >. Multi-line uses / \ for the first row,
// \ / for the last row, and | | for the middle rows.
func borderChars(i, n int) (string, string) {
	if n == 1 {
		return "<", ">"
	}
	switch i {
	case 0:
		return "/", "\\"
	case n - 1:
		return "\\", "/"
	default:
		return "|", "|"
	}
}

// wrap splits text into lines no longer than width, breaking on spaces.
// Words longer than width are hard-split.
func wrap(text string, width int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return []string{""}
	}

	var lines []string
	cur := ""
	for _, w := range words {
		// hard-split a single word that is too long
		for len(w) > width {
			if cur != "" {
				lines = append(lines, cur)
				cur = ""
			}
			lines = append(lines, w[:width])
			w = w[width:]
		}
		if cur == "" {
			cur = w
		} else if len(cur)+1+len(w) <= width {
			cur = cur + " " + w
		} else {
			lines = append(lines, cur)
			cur = w
		}
	}
	if cur != "" {
		lines = append(lines, cur)
	}
	return lines
}

// maxLen returns the length of the longest line.
func maxLen(lines []string) int {
	m := 0
	for _, ln := range lines {
		if len(ln) > m {
			m = len(ln)
		}
	}
	return m
}

// cow is the classic happy cow, aligned under the bubble.
const cow = `        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
`
