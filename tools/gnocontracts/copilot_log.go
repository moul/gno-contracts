package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"
)

// The review log, and why a workflow rather than an instruction.
//
// Copilot code review comments on a pull request and cannot post anywhere else,
// so "have it share its thinking on a meta issue" is not something an
// instructions file can ask for. What it can be is mechanical: when Copilot
// submits a review, take what it actually wrote and append one digest to the
// hub issue.
//
// This half is the FORMATTER, and it is deliberately network-free: it reads one
// JSON document on stdin ({pr, review, comments}) and writes markdown on stdout.
// The workflow does the two `gh api` calls and the `gh issue comment`. That
// split is the same rule the companions follow, transport separated from
// parsing, and it is what makes this testable against a real captured review
// (testdata/copilot-review.json) instead of against a mock.
//
// The digest is shaped around ONE question, because a log nobody acts on is a
// log nobody reads: for each finding, was it real, and if it was not, which
// line of the instructions produced it? Every entry ships with the two
// checkboxes and a blank for the config change it earned. That is the flywheel:
// a false positive is not noise to be tolerated, it is a defect in
// .github/copilot-instructions.md or .github/instructions/*.instructions.md,
// and it has a fix.

// copilotLogins are the two identities one Copilot review arrives under: the
// review itself is submitted by the bot, while its inline comments are authored
// by "Copilot". Matching only one of them silently logs an empty review.
var copilotLogins = map[string]bool{
	"copilot-pull-request-reviewer[bot]": true,
	"Copilot":                            true,
}

type copilotPR struct {
	Number  int    `json:"number"`
	Title   string `json:"title"`
	HTMLURL string `json:"html_url"`
	User    string `json:"user"`
}

type copilotReview struct {
	ID          int64  `json:"id"`
	State       string `json:"state"`
	Body        string `json:"body"`
	HTMLURL     string `json:"html_url"`
	SubmittedAt string `json:"submitted_at"`
	User        struct {
		Login string `json:"login"`
	} `json:"user"`
}

type copilotComment struct {
	ID           int64  `json:"id"`
	Path         string `json:"path"`
	Line         *int   `json:"line"`
	OriginalLine *int   `json:"original_line"`
	Body         string `json:"body"`
	HTMLURL      string `json:"html_url"`
	InReplyTo    *int64 `json:"in_reply_to_id"`
	User         struct {
		Login string `json:"login"`
	} `json:"user"`
}

type copilotPayload struct {
	PR       copilotPR        `json:"pr"`
	Review   copilotReview    `json:"review"`
	Comments []copilotComment `json:"comments"`
}

// copilotVerdictRe pulls the one-line verdict out of the review overview, which
// Copilot writes as a level-3 heading ("### 🟡 Changes recommended").
var copilotVerdictRe = regexp.MustCompile(`(?m)^###\s+(.+?)\s*$`)

// htmlTagRe strips the inline <picture>/<img> severity badges out of the
// overview. They are 400 characters each and say nothing in a plain-text digest.
var htmlTagRe = regexp.MustCompile(`<[^>]+>`)

// copilotTitleRe matches the short title Copilot writes for each finding in its
// own overview list, linked to the inline comment by anchor:
//
//	[Standard-library rule incorrectly excludes approved tooling dependencies](#discussion_r4137622915)
//
// Those titles are better than anything derivable from the comment body, which
// opens with the evidence rather than the claim, so the digest prefers them and
// only falls back to a first sentence when the overview has none.
var copilotTitleRe = regexp.MustCompile(`(?m)^-[^\n]*?(?:copilot-code-review/(high|medium|low)-v2[^\n]*?</picture>)?\s*\[([^\n]+)\]\(#discussion_r(\d+)\)`)

// copilotMissedRe is one "Previously missed" finding: a summary carrying a
// severity badge and a headline, then its location in backticks. These exist
// ONLY in the overview body, with no thread and no inline comment, so a digest
// built from comments alone drops them: 7 of #289's 12 findings were this kind.
var copilotMissedRe = regexp.MustCompile("(?s)<summary><picture>.*?copilot-code-review/(high|medium|low)-v2.*?</picture>\\s*(.*?)</summary>\\s*`([^`]+)`")

// copilotTitles maps comment id to Copilot's own headline for it.
// copilotTitle is Copilot's own headline for a thread, and the severity badge
// next to it when the overview carries one.
type copilotTitle struct{ Title, Severity string }

// copilotTitles maps a thread id to its overview headline. The headline runs
// to the LAST "](#discussion_r" on its line, because a code-shaped headline
// ("Bounds-check items[i]") carries brackets of its own.
func copilotTitles(overview string) map[string]copilotTitle {
	out := map[string]copilotTitle{}
	for _, m := range copilotTitleRe.FindAllStringSubmatch(overview, -1) {
		title := strings.TrimSpace(htmlTagRe.ReplaceAllString(m[2], ""))
		if title != "" {
			out[m[3]] = copilotTitle{Title: title, Severity: m[1]}
		}
	}
	return out
}

// copilotMissed is a "Previously missed" finding from the overview body.
type copilotMissed struct{ Title, Severity, Where string }

func copilotMissedFindings(overview string) []copilotMissed {
	i := strings.Index(overview, "Previously missed")
	if i < 0 {
		return nil
	}
	var out []copilotMissed
	for _, m := range copilotMissedRe.FindAllStringSubmatch(overview[i:], -1) {
		out = append(out, copilotMissed{
			Title:    strings.TrimSpace(htmlTagRe.ReplaceAllString(m[2], "")),
			Severity: m[1],
			Where:    strings.ReplaceAll(m[3], "\u200b", ""), // GitHub breaks paths with zero-width spaces
		})
	}
	return out
}

func cmdCopilotLog(_ string, args []string) error {
	in := io.Reader(os.Stdin)
	if len(args) == 1 {
		f, err := os.Open(args[0])
		if err != nil {
			return err
		}
		defer f.Close()
		in = f
	} else if len(args) > 1 {
		return fmt.Errorf("usage: copilot-log [payload.json]  (default: stdin)")
	}

	var p copilotPayload
	if err := json.NewDecoder(in).Decode(&p); err != nil {
		return fmt.Errorf("reading the payload: %w", err)
	}
	body, ok := copilotDigest(p)
	if !ok {
		// Not a Copilot review. Emitting nothing rather than erroring lets the
		// workflow guard on an empty body instead of on an exit code, which is
		// the shape that does not turn a human review into a failed run.
		return nil
	}
	fmt.Print(body)
	return nil
}

// copilotDigest renders the hub comment. The bool is false when the payload is
// not a Copilot review at all.
func copilotDigest(p copilotPayload) (string, bool) {
	if !copilotLogins[p.Review.User.Login] {
		return "", false
	}

	var b strings.Builder
	fmt.Fprintf(&b, "## [#%d](%s) %s\n\n", p.PR.Number, p.PR.HTMLURL, copilotInline(p.PR.Title))
	fmt.Fprintf(&b, "**%s** · [the review](%s)", copilotVerdict(p.Review.Body), p.Review.HTMLURL)
	if p.Review.SubmittedAt != "" {
		fmt.Fprintf(&b, " · %s", p.Review.SubmittedAt)
	}
	b.WriteString("\n\n")

	findings := copilotFindings(p.Comments)
	missed := copilotMissedFindings(p.Review.Body)
	if len(findings) == 0 && len(missed) == 0 {
		b.WriteString("No inline findings. A clean review is a data point too: it is what says\n" +
			"the reviewer is not simply always finding something.\n")
		return b.String(), true
	}

	fmt.Fprintf(&b, "%d finding(s). **Tick one per finding**, and a false positive owes a\n"+
		"config change, because that is the only thing that stops the next one.\n\n", len(findings)+len(missed))

	titles := copilotTitles(p.Review.Body)
	for _, c := range findings {
		t := titles[strconv.FormatInt(c.ID, 10)]
		if t.Title == "" {
			t.Title = copilotHeadline(c.Body)
		}
		fmt.Fprintf(&b, "### %s\n\n", copilotHeading(t.Title, t.Severity, false))
		fmt.Fprintf(&b, "%s%s · [comment](%s)\n\n", copilotCodeSpan(c.Path), copilotAtLine(c), c.HTMLURL)
		copilotBoxes(&b)
	}
	for _, m := range missed {
		fmt.Fprintf(&b, "### %s\n\n", copilotHeading(m.Title, m.Severity, true))
		fmt.Fprintf(&b, "%s · in the overview, no thread\n\n", copilotCodeSpan(m.Where))
		copilotBoxes(&b)
	}
	return b.String(), true
}

// copilotHeading is the escaped headline, flagged when it came from the
// "Previously missed" section, with the severity badge as a word. Copilot's
// headline is escaped like the title: it quotes code, and code carries
// brackets, underscores and the odd @.
func copilotHeading(title, severity string, missed bool) string {
	h := copilotInline(title)
	if missed {
		h = "Previously missed: " + h
	}
	if severity != "" {
		h += " (" + severity + ")"
	}
	return h
}

func copilotBoxes(b *strings.Builder) {
	b.WriteString("- [ ] real, and fixed\n")
	b.WriteString("- [ ] false positive. Which line of the instructions produced it: \n")
	b.WriteString("- [ ] a finding about `EFFECTIVE_GNO.md` or `AGENTS.md`, not about the code\n\n")
}

// copilotCodeSpan renders s as one inline code span whatever it holds. A path
// is the pull request's to choose, and one carrying a backtick and a newline
// would otherwise close the span and write its own markdown into the hub
// issue. Line breaks fold to spaces, and the fence is one backtick longer than
// the longest run inside, which is how CommonMark nests them.
func copilotCodeSpan(s string) string {
	s = strings.Join(strings.FieldsFunc(s, func(r rune) bool { return r == '\n' || r == '\r' }), " ")
	longest, run := 0, 0
	for _, r := range s {
		if r == '`' {
			run++
			longest = max(longest, run)
		} else {
			run = 0
		}
	}
	fence := strings.Repeat("`", longest+1)
	if longest > 0 {
		return fence + " " + s + " " + fence
	}
	return fence + s + fence
}

// copilotFindings keeps Copilot's own top-level inline comments, dropping
// replies (ours and its own) so the log records findings and not conversation.
func copilotFindings(cs []copilotComment) []copilotComment {
	out := make([]copilotComment, 0, len(cs))
	for _, c := range cs {
		if c.InReplyTo != nil || !copilotLogins[c.User.Login] {
			continue
		}
		out = append(out, c)
	}
	return out
}

// copilotVerdict is the "### 🟡 Changes recommended" line from the overview, or
// the review state when the overview has no heading.
func copilotVerdict(body string) string {
	if m := copilotVerdictRe.FindStringSubmatch(body); m != nil {
		if v := strings.TrimSpace(htmlTagRe.ReplaceAllString(m[1], "")); v != "" {
			return v
		}
	}
	return "reviewed"
}

// copilotHeadline is the first sentence of a finding, which is what makes the
// log skimmable. The full text stays one link away rather than being copied
// here: a hub issue that reproduces every review in full is a second inbox.
func copilotHeadline(body string) string {
	s := strings.TrimSpace(htmlTagRe.ReplaceAllString(body, ""))
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.Join(strings.Fields(s), " ")
	if i := strings.Index(s, ". "); i > 0 && i < 200 {
		s = s[:i]
	}
	const max = 140
	if len(s) > max {
		s = strings.TrimSpace(s[:max]) + "…"
	}
	if s == "" {
		return "(empty finding)"
	}
	return s
}

// copilotAtLine renders ":<line>" when the API gave one. `line` is null on a
// comment whose diff hunk has moved, and `original_line` is the one that
// survives, which is why both are read.
func copilotAtLine(c copilotComment) string {
	n := c.Line
	if n == nil {
		n = c.OriginalLine
	}
	if n == nil {
		return ""
	}
	return fmt.Sprintf(":%d", *n)
}

// copilotInline neutralises the markdown in a PR title, which is a string a
// contributor chose. Same rule the realms follow for a caller's string.
//
// The BACKSLASH is escaped first, and it is the one that matters. Escaping "["
// to "\[" without it turns a title already containing `\[click\](http://evil)`
// into `\\[click\\](http://evil)`, and CommonMark reads each `\\` as an escaped
// backslash, leaving the brackets ACTIVE: a contributor-chosen live link in the
// hub issue. strings.NewReplacer makes one left-to-right pass and never
// reprocesses its own output, so listing it first is sufficient.
//
// Angle brackets go too, because <http://host> is an autolink and <b> is inline
// HTML, neither of which a title should be able to produce. And an @ is broken
// up, because the hub issue would otherwise notify whoever a title names.
func copilotInline(s string) string {
	r := strings.NewReplacer(
		"\\", "\\\\",
		"[", "\\[", "]", "\\]",
		"<", "\\<", ">", "\\>",
		"`", "\\`", "*", "\\*", "_", "\\_",
		"\n", " ",
		// A backslash does not stop a mention, and the bot reposting
		// "@org/team" would notify that team. A zero-width space does.
		"@", "@\u200b",
	)
	return r.Replace(s)
}
