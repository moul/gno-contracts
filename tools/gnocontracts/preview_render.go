package main

// The two things a preview writes besides HTML: its own index page, and the
// markdown fragment the pull request comment folds in.

import (
	"fmt"
	"html"
	"os"
	"path"
	"strings"
)

// previewIndex is the snapshot's own landing page: what was rendered, and a
// link to each package. It is deliberately dependency-free markup — the
// gnoweb assets belong to the captured pages, not to this.
func previewIndex(plan *previewPlan, c *Crawler, pr string) string {
	var b strings.Builder
	title := "gno-contracts — main"
	lede := fmt.Sprintf("Every package on <code>main</code>, rendered with gnodev/gnoweb: %d package(s), %d page(s).",
		len(plan.Paths), plan.Pages)
	if plan.Mode == "pr" {
		title = "gno-contracts — pull request preview"
		if pr != "" {
			title = fmt.Sprintf("gno-contracts — PR #%s", html.EscapeString(pr))
		}
		lede = fmt.Sprintf("%d package(s) changed or affected, %d page(s).", len(plan.Paths), plan.Pages)
	}

	b.WriteString(`<!doctype html>
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>` + title + `</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;max-width:52rem;margin:3rem auto;padding:0 1.2rem;line-height:1.5;color:#1a1a1a}
h1{font-size:1.4rem;margin-bottom:.2rem}h2{font-size:1rem;margin:2rem 0 .4rem;color:#555;text-transform:uppercase;letter-spacing:.04em}
p.lede{color:#555;margin-top:0}
ul{list-style:none;padding:0;columns:2;column-gap:2rem}li{margin:.15rem 0;break-inside:avoid}
code{font-family:ui-monospace,monospace;font-size:.88em}
a{color:#0b5;text-decoration:none}a:hover{text-decoration:underline}
footer{margin-top:3rem;color:#888;font-size:.85rem;border-top:1px solid #eee;padding-top:1rem}
@media (prefers-color-scheme:dark){body{background:#111;color:#eee}p.lede,h2{color:#aaa}footer{color:#777;border-color:#333}}
</style>
<h1>` + title + `</h1>
<p class="lede">` + lede + `</p>
`)

	if plan.Mode == "pr" {
		writePkgSection(&b, "Changed", plan.Changed, c)
		writePkgSection(&b, "Affected (imports what changed)", plan.Dependents, c)
		if plan.Dropped > 0 {
			fmt.Fprintf(&b, "<p>%d further affected package(s) were dropped by the cap.</p>\n", plan.Dropped)
		}
	} else {
		var realms, pure []string
		for _, p := range plan.Paths {
			if strings.Contains(p, "/r/") {
				realms = append(realms, p)
			} else {
				pure = append(pure, p)
			}
		}
		writePkgSection(&b, fmt.Sprintf("Realms (%d)", len(realms)), realms, c)
		writePkgSection(&b, fmt.Sprintf("Packages (%d)", len(pure)), pure, c)
	}

	b.WriteString(`<footer>A static snapshot of a fresh local chain: every package renders its state
right after <code>init()</code>. Transactions, the faucet and search do not work, and a link
that leaves this snapshot goes to the live site.</footer>
`)
	return b.String()
}

func writePkgSection(b *strings.Builder, heading string, pkgs []string, c *Crawler) {
	if len(pkgs) == 0 {
		return
	}
	fmt.Fprintf(b, "<h2>%s</h2>\n<ul>\n", html.EscapeString(heading))
	for _, p := range pkgs {
		href, ok := c.FileOf(gnowebPath(p))
		if !ok {
			continue
		}
		fmt.Fprintf(b, "  <li><a href=%q><code>%s</code></a></li>\n",
			path.Dir(href)+"/", html.EscapeString(p))
	}
	b.WriteString("</ul>\n")
}

// previewComment is the section the pull request comment folds in under its
// preview link: the before/after pictures first, then what was rendered.
//
// It is a fragment, not a comment: `gnocontracts pr` owns the one sticky
// comment, and this is handed to it with -preview-detail.
func previewComment(plan *previewPlan, baseURL string) string {
	base := strings.TrimSuffix(baseURL, "/")
	var b strings.Builder

	if len(plan.Pairs) > 0 {
		b.WriteString("<table><tr>\n")
		for _, p := range plan.Pairs {
			cells := []string{}
			if p.Before != "" {
				cells = append(cells, imgCell(base, p.Before, p.URL, "before"))
			} else if p.New {
				cells = append(cells, "<td align=\"center\"><sub>new in this PR</sub></td>")
			}
			cells = append(cells, imgCell(base, p.After, p.URL, "after"))
			fmt.Fprintf(&b, "<td><b><code>%s</code></b><table><tr>%s</tr></table></td>\n",
				p.Pkg, strings.Join(cells, ""))
		}
		b.WriteString("</tr></table>\n\n")
	}

	var lines []string
	for _, p := range plan.Changed {
		lines = append(lines, fmt.Sprintf("- [`%s`](%s%s/) · [source](%s%s/_t/source/)%s",
			p, base, gnowebPath(p), base, gnowebPath(p), newTag(plan, p)))
	}
	for _, p := range plan.Dependents {
		lines = append(lines, fmt.Sprintf("- [`%s`](%s%s/) · imports what changed", p, base, gnowebPath(p)))
	}
	if plan.Dropped > 0 {
		lines = append(lines, fmt.Sprintf("- _%d more affected package(s) not rendered (cap)_", plan.Dropped))
	}
	if len(lines) > 0 {
		b.WriteString(strings.Join(lines, "\n") + "\n")
	}
	return b.String()
}

func imgCell(base, shot, pageURL, label string) string {
	return fmt.Sprintf(`<td width="50%%" align="center"><a href="%s/%s"><img src="%s/%s" width="100%%" alt="%s"></a><br><sub>%s</sub></td>`,
		base, pageURL, base, shot, label, label)
}

func newTag(plan *previewPlan, pkg string) string {
	for _, n := range plan.New {
		if n == pkg {
			return " · **new**"
		}
	}
	return ""
}

// readPreviewDetail returns the fragment written by `preview`, or "" when there
// is none: the pull request comment is rendered before the preview exists, and
// again once it does.
func readPreviewDetail(p string) string {
	if p == "" {
		return ""
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(b), "\n")
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
