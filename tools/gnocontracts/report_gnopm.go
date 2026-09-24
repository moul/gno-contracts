package main

import (
	"os"
	"strings"
)

// The gnopm verdict, folded into the one comment this repository posts.
//
// `gnopm tool ci` is the gate (see .github/workflows/ci.yml) and it writes its
// report to the job summary, which is a page nobody opens unless something is
// already known to be wrong. The verdict that matters most when a pull request
// touches gnomod.lock was therefore the one verdict a reviewer could not see
// from the pull request itself.
//
// Rendering it here rather than letting `gnopm tool ci --comment` post its own
// is the same decision pr.go made for the preview and the labels: one comment,
// one author. gnopm already writes Markdown, so this only decides where it
// goes and how loud it is.

// gnopmFragment turns `gnopm tool ci` output into a section of the comment.
//
// Two things are dropped, and one is kept. The HTML marker is how gnopm finds
// its OWN sticky comment to edit; leaving it in a comment gnocontracts owns
// would hand gnopm a second claim on it the day someone turns --comment on.
// gnopm's "What this changes in gnomod.lock" section is the same list
// report_lock.go already renders from the same lock, so keeping both would
// print it twice. The attribution line stays: inside a section this comment
// owns, it is the only thing that says which tool produced the table.
func gnopmFragment(report string) string {
	report = strings.TrimSpace(report)
	if report == "" {
		return ""
	}
	var keep []string
	dropping := false
	for _, ln := range strings.Split(report, "\n") {
		trimmed := strings.TrimSpace(ln)
		switch {
		case strings.HasPrefix(trimmed, "<!--"):
			continue
		case strings.HasPrefix(ln, "**What this changes in"):
			dropping = true
			continue
		// The attribution closes the report, so it is also what ends the
		// section being dropped. Stopping at the end of the input instead
		// would keep the attribution only on the pull requests that did not
		// touch the lock, which is the sort of difference nobody notices and
		// everybody has to explain later.
		case dropping && strings.HasPrefix(trimmed, "<sub>"):
			dropping = false
		case dropping:
			continue
		}
		keep = append(keep, ln)
	}
	body := strings.TrimSpace(strings.Join(keep, "\n"))
	if body == "" {
		return ""
	}

	// Green folds away, anything else does not. A reviewer should never have to
	// expand a section to find out that it is red, and should never have to
	// scroll past one to find out that it is fine.
	if !strings.Contains(body, "❌") && !strings.Contains(body, "⚠️") {
		return details("🔒 `gnomod.lock` · gnopm: every check green", body+"\n")
	}
	return body + "\n"
}

// readGnopmReport reads what `gnopm tool ci` wrote, or nothing.
//
// A missing file is not an error: the comment is rendered on every pull
// request, including the ones where the gnopm step was skipped or failed
// before it could write anything, and a comment that refuses to render is
// worse than one missing a section.
func readGnopmReport(path string) string {
	if path == "" {
		return ""
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return gnopmFragment(string(b))
}
