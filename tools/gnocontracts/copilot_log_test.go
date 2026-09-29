package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// realReview is a Copilot review captured from moul/gno-contracts#274 on
// 2026-09-29, kept verbatim so the formatter is tested against what the API
// actually sends rather than against a hand-written guess at it.
func realReview(t *testing.T) copilotPayload {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", "copilot-review.json"))
	if err != nil {
		t.Fatal(err)
	}
	var p copilotPayload
	if err := json.Unmarshal(b, &p); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestCopilotDigestOnARealReview(t *testing.T) {
	got, ok := copilotDigest(realReview(t))
	if !ok {
		t.Fatal("a Copilot review must render")
	}
	for _, want := range []string{
		"[#274](https://github.com/moul/gno-contracts/pull/274)",
		"**🟡 Changes recommended**",
		"3 finding(s)",
		// Copilot's own headline for the finding, not the comment's first
		// sentence, which opens with evidence rather than the claim.
		"### Standard-library rule incorrectly excludes approved tooling dependencies",
		"`.github/instructions/go.instructions.md`:12",
		"- [ ] false positive. Which line of the instructions produced it:",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("digest is missing %q\n---\n%s", want, got)
		}
	}
	if n := strings.Count(got, "\n### "); n != 3 {
		t.Errorf("want 3 finding headings, got %d\n---\n%s", n, got)
	}
}

func TestCopilotDigestSkipsAHumanReview(t *testing.T) {
	p := realReview(t)
	p.Review.User.Login = "moul"
	if body, ok := copilotDigest(p); ok || body != "" {
		t.Fatalf("a human review must not be logged, got ok=%v body=%q", ok, body)
	}
}

// A clean review is worth logging: it is what says the reviewer is not simply
// always finding something.
func TestCopilotDigestLogsACleanReview(t *testing.T) {
	p := realReview(t)
	p.Comments = nil
	got, ok := copilotDigest(p)
	if !ok {
		t.Fatal("a clean Copilot review still renders")
	}
	if !strings.Contains(got, "No inline findings") {
		t.Errorf("want the clean-review line, got:\n%s", got)
	}
	if strings.Contains(got, "- [ ]") {
		t.Errorf("a clean review carries no checkboxes, got:\n%s", got)
	}
}

// The log records findings, not conversation: our replies and Copilot's own
// follow-ups are threaded under a finding and must not become new entries.
func TestCopilotDigestDropsReplies(t *testing.T) {
	p := realReview(t)
	parent := p.Comments[0].ID
	p.Comments = append(p.Comments, copilotComment{
		ID: 99, Path: "x.go", Body: "replying", InReplyTo: &parent,
	})
	p.Comments[len(p.Comments)-1].User.Login = "Copilot"

	got, _ := copilotDigest(p)
	if !strings.Contains(got, "3 finding(s)") {
		t.Errorf("a reply is not a finding, got:\n%s", got)
	}
}

// `line` is null on a comment whose diff hunk has moved; `original_line` is the
// one that survives. Reading only the first drops the location silently.
func TestCopilotAtLineFallsBackToOriginalLine(t *testing.T) {
	n := 42
	if got := copilotAtLine(copilotComment{OriginalLine: &n}); got != ":42" {
		t.Errorf("want :42 from original_line, got %q", got)
	}
	m := 7
	if got := copilotAtLine(copilotComment{Line: &m, OriginalLine: &n}); got != ":7" {
		t.Errorf("line wins when present, got %q", got)
	}
	if got := copilotAtLine(copilotComment{}); got != "" {
		t.Errorf("no line at all renders nothing, got %q", got)
	}
}

func TestCopilotHeadlineIsUsedWhenTheOverviewHasNoTitles(t *testing.T) {
	p := realReview(t)
	p.Review.Body = "### 🟢 Looks good\n\nno anchor list here"
	got, _ := copilotDigest(p)
	if !strings.Contains(got, "### Because this file applies to every") {
		t.Errorf("want the first-sentence fallback, got:\n%s", got)
	}
	if !strings.Contains(got, "**🟢 Looks good**") {
		t.Errorf("want the verdict from the overview heading, got:\n%s", got)
	}
}

func TestCopilotVerdictFallsBackWhenTheOverviewHasNoHeading(t *testing.T) {
	if got := copilotVerdict("just prose"); got != "reviewed" {
		t.Errorf("want the fallback verdict, got %q", got)
	}
}

// A pull request title is a string a contributor chose, and the digest goes
// into an issue body. Same rule the realms follow for a caller's string.
func TestCopilotDigestNeutralisesThePRTitle(t *testing.T) {
	p := realReview(t)
	p.PR.Title = "fix [thing](http://evil) `code` *bold*"
	got, _ := copilotDigest(p)
	if strings.Contains(got, "[thing](http://evil)") {
		t.Errorf("the title must not stay live markdown, got:\n%s", got)
	}
	if !strings.Contains(got, "\\[thing\\]") {
		t.Errorf("want the escaped title, got:\n%s", got)
	}
}
