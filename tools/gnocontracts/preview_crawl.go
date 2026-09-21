package main

// The crawler behind `gnocontracts preview`: it snapshots a running gnoweb into
// a self-contained static tree.
//
// Adapted from the gnoweb preview renderer proposed upstream in
// gnolang/gno#6194 (misc/gnopreview). The crawl, the slugging and the URL
// rewriting are the same problem in both places, so the shapes are kept close
// on purpose: a fix landing on one side should be readable as a patch for the
// other. What differs is the planning around it — see preview.go — because this
// repository versions packages in gnomod.toml rather than in the directory
// path, and its previews cover pure packages too, not only realms.

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"
)

// A pvPage is one crawled gnoweb response.
type pvPage struct {
	URL  string // gnoweb path, e.g. /r/moul/hello/v0$source&file=hello.gno
	File string // output file, e.g. r/moul/hello/v0/_t/source-file-hello.gno-1f2e/index.html
	Body string
}

// noindexTag keeps previews out of search results. Every snapshot page is a
// near-duplicate of a real gno.land page, so an indexed preview competes with
// the site it is a copy of — and outlives the pull request in the index.
//
// A meta tag rather than robots.txt: a path disallowed in robots.txt can still
// be indexed from an external link, and being disallowed is exactly what stops
// a crawler from ever reading the noindex. Allow the crawl, refuse the index.
const noindexTag = `<meta name="robots" content="noindex, nofollow">`

var (
	pvHeadRe   = regexp.MustCompile(`(?i)<head[^>]*>`)
	pvRobotsRe = regexp.MustCompile(`(?i)<meta\s+name="robots"[^>]*>`)
	pvAttrRe   = regexp.MustCompile(`(?i)\b(href|src)="([^"]*)"`)
	pvCSSRe    = regexp.MustCompile(`url\(\s*"?(/public/[^)"']*)"?\s*\)`)
)

// Crawler snapshots a running gnoweb into a self-contained static tree.
type Crawler struct {
	Base     string   // http://127.0.0.1:8899
	Paths    []string // package paths that may be followed (realms and pure packages)
	MaxPages int
	Live     string // absolute origin for links we did not capture
	// RenderOnly captures just each package's landing page and follows nothing.
	// Used for the "before" pass, where only the rendered output is compared.
	RenderOnly bool
	// Prefix is prepended to every output path, so a second crawl of the same
	// packages can live beside the first (the "before" tree under _before/).
	Prefix string
	// ChangedFiles maps a package path to the files the pull request touched. A
	// package listed here gets a per-file $source page for those files and no
	// others; a package absent from it gets at most FileBudget of them.
	//
	// Empty in site mode, where every file is worth a page: this repository has
	// 209 non-test .gno files in total, so the whole corpus costs less than one
	// wide monorepo preview.
	ChangedFiles map[string][]string
	// FileBudget is how many per-file source pages a package with no changed
	// files may still keep. 0 in pull-request mode: a package pulled in because
	// it imports what changed has nothing to look at file by file. Negative
	// means no budget at all, i.e. keep every file.
	FileBudget int
	// ArgBudget caps render-argument pages (`:page/3`) per package.
	//
	// This is the one axis of a gno preview that is genuinely unbounded: a
	// realm is free to link a page per value it knows about. Measured on this
	// repository 2026-09-21, r/moul/x/daily/romannumdemo enumerates one render
	// argument per numeral and produced 4,065 of the snapshot's 5,437 pages and
	// 220 MB of its 323 MB, by itself. A sample shows what the argument view
	// renders; the enumeration is the realm's job, not the preview's.
	ArgBudget int

	fileBudget map[string]int
	argBudget  map[string]int

	pages map[string]*pvPage
	order []string
}

// unlimitedFiles is the FileBudget that keeps every per-file source page.
const unlimitedFiles = -1

// Seeds returns the entry points for the selected packages, plus the directory
// pages above them. Everything else is reached by following links.
func (c *Crawler) Seeds() []string {
	seen := map[string]bool{}
	var out []string
	add := func(u string) {
		if !seen[u] {
			seen[u] = true
			out = append(out, u)
		}
	}
	dirs := map[string]bool{}
	for _, p := range c.Paths {
		u := gnowebPath(p)
		add(u)
		if c.RenderOnly {
			continue
		}
		add(u + "$source")
		add(u + "$help")
		// Walk up to the directory pages, but stop above "/r": gnoweb answers a
		// single-segment path with 400, so seeding it only buys a logged error.
		for d := path.Dir(u); strings.Count(d, "/") >= 2; d = path.Dir(d) {
			dirs[d] = true
		}
	}
	if !c.RenderOnly {
		for _, d := range sortedStrings(dirs) {
			add(d)
		}
	}
	return out
}

// Run crawls from the seeds, following only links that stay inside the selected
// packages (or the directory pages we seeded).
func (c *Crawler) Run() error {
	c.pages = map[string]*pvPage{}
	seeds := c.Seeds()
	seedSet := map[string]bool{}
	for _, s := range seeds {
		seedSet[s] = true
	}

	queue := append([]string(nil), seeds...)
	visited := map[string]bool{}
	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]
		if visited[u] {
			continue
		}
		visited[u] = true
		if c.MaxPages > 0 && len(c.pages) >= c.MaxPages {
			return fmt.Errorf("page cap %d reached (queue still had %d)", c.MaxPages, len(queue)+1)
		}
		body, code, err := c.getRetry(u)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  ! %s: %v\n", u, err)
			continue
		}
		if code != http.StatusOK {
			fmt.Fprintf(os.Stderr, "  ! %s: HTTP %d\n", u, code)
			continue
		}
		if !c.charge(u) {
			continue
		}
		p := &pvPage{URL: u, File: path.Join(c.Prefix, urlToFile(u)), Body: body}
		c.pages[u] = p
		c.order = append(c.order, u)

		for _, link := range pageLinks(body) {
			if !visited[link] && (seedSet[link] || c.inScope(link)) {
				queue = append(queue, link)
			}
		}
	}
	return nil
}

// Pages is how many pages the crawl captured.
func (c *Crawler) Pages() int { return len(c.pages) }

// explosiveArgs are gnoweb web-query keys whose links enumerate the chain state
// object graph: following them multiplies pages without bound and trips
// gnoweb's per-IP $state rate limiter.
var explosiveArgs = map[string]bool{
	"oid":      true, // state explorer object id
	"tid":      true, // state explorer type id
	"download": true, // raw file bytes, not a page
	// $help already lists every exported function with its form; $help&func=X
	// only preselects one, at one page per function.
	"func": true,
	// The state explorer serializes the whole realm object graph on a chain
	// that only ever ran init(). Run gnodev locally for it.
	"state": true,
}

// inScope reports whether a gnoweb path belongs to one of the selected packages
// and is a page worth snapshotting. Render arguments (:p/about) and the tab
// query ($source&file=a.gno) are part of the same page family, so they are
// followed; anything else is left to the live site.
func (c *Crawler) inScope(p string) bool {
	if c.RenderOnly {
		return false
	}
	base, args, query := splitGnowebURL(p)
	// $source and $help do not depend on the render arguments, so ":x$source"
	// is a byte-for-byte copy of "$source". Keep the render view of each
	// argument set, and the argument-free tabs.
	if args != "" && query != "" {
		return false
	}
	// "/r/x/y/" is gnoweb's listing view, a different page from the render at
	// "/r/x/y". Keep the render and let the listing fall through to the live
	// site — a preview is about what a package renders.
	if strings.HasSuffix(base, "/") {
		return false
	}
	pkg := ""
	for _, r := range c.Paths {
		if base == gnowebPath(r) {
			pkg = r
			break
		}
	}
	if pkg == "" {
		return false
	}
	if args != "" && c.argBudget[pkg] >= c.ArgBudget {
		return false
	}
	for _, part := range strings.Split(query, "&") {
		key, val, _ := strings.Cut(part, "=")
		if explosiveArgs[key] {
			return false
		}
		if key == "file" && !c.wantFile(pkg, val) {
			return false
		}
	}
	return true
}

// wantFile decides whether a package's $source&file=<name> page is worth
// keeping. Per-file source pages are the bulk of a wide preview, and on a pull
// request a reviewer wants the files the pull request touched.
//
// This only tests the budget. Charging it is chargeFile's job, called once the
// page is actually captured — a link that is discovered and then 404s must not
// spend a slot that a page which really exists could have used.
func (c *Crawler) wantFile(pkg, name string) bool {
	if changed, ok := c.ChangedFiles[pkg]; ok {
		return slices.Contains(changed, name)
	}
	return c.FileBudget == unlimitedFiles || c.fileBudget[pkg] < c.FileBudget
}

// charge spends the budget a captured page costs, and reports whether it may be
// kept. Charging happens here rather than at link discovery because a link that
// is found and then 404s must not spend a slot a real page could have used —
// and because a breadth-first crawl discovers far more links than it captures,
// so the check in inScope is advisory and this one is authoritative.
func (c *Crawler) charge(u string) bool {
	base, args, query := splitGnowebURL(u)
	pkg := ""
	for _, r := range c.Paths {
		if base == gnowebPath(r) {
			pkg = r
			break
		}
	}
	if pkg == "" {
		return true // a directory page: not attributable to one package
	}
	if args != "" {
		if c.argBudget == nil {
			c.argBudget = map[string]int{}
		}
		if c.argBudget[pkg] >= c.ArgBudget {
			return false
		}
		c.argBudget[pkg]++
	}
	name := ""
	for _, part := range strings.Split(query, "&") {
		if k, v, _ := strings.Cut(part, "="); k == "file" {
			name = v
		}
	}
	if name == "" || c.FileBudget == unlimitedFiles {
		return true
	}
	if _, listed := c.ChangedFiles[pkg]; listed {
		return true // gated by the changed set, not the budget
	}
	if c.fileBudget == nil {
		c.fileBudget = map[string]int{}
	}
	if c.fileBudget[pkg] >= c.FileBudget {
		return false
	}
	c.fileBudget[pkg]++
	return true
}

// splitGnowebURL breaks a gnoweb path into its three components. gnoweb puts
// them all in the path: ":" opens the render arguments, "$" the web query.
//
//	/r/x/y                     -> "/r/x/y", "",        ""
//	/r/x/y$source&file=a.gno   -> "/r/x/y", "",        "source&file=a.gno"
//	/r/x/y:p/about$source      -> "/r/x/y", "p/about", "source"
//
// The trailing slash is NOT trimmed: in gnoweb "/r/x/y" renders and "/r/x/y/"
// lists, and they are different pages. Collapsing them would map both onto one
// file and let one overwrite the other.
func splitGnowebURL(p string) (base, args, query string) {
	if i := strings.Index(p, "$"); i >= 0 {
		p, query = p[:i], p[i+1:]
	}
	if i := strings.Index(p, ":"); i >= 0 {
		p, args = p[:i], p[i+1:]
	}
	return p, args, query
}

// canonicalURL gives one spelling to a page gnoweb links to in several orders:
// templates emit both "$source&file=a.gno" and "$file=a.gno&source".
func canonicalURL(p string) string {
	base, args, query := splitGnowebURL(p)
	if args != "" {
		base += ":" + args
	}
	if query == "" {
		return base
	}
	parts := strings.Split(query, "&")
	sort.Strings(parts)
	return base + "$" + strings.Join(parts, "&")
}

// Write renders the captured pages into dir with every absolute gnoweb URL
// rewritten: to a relative path when we captured the target, to the live site
// otherwise. assets is gnoweb's public/ dir inside GNOROOT, copied verbatim.
func (c *Crawler) Write(dir, assets string) error {
	if assets == "" { // a prefixed crawl reuses the assets already written
		return c.writePages(dir)
	}
	n, err := copyAssets(assets, filepath.Join(dir, "public"))
	if err != nil {
		return fmt.Errorf("copy assets: %w", err)
	}
	// js/index.js has carried a hardcoded "/public/js/controller-" prefix since
	// the controller loader was introduced. If that ever stops being true the
	// snapshot silently loses every interactive control, so say so.
	if n == 0 {
		fmt.Fprintln(os.Stderr, "  ! no absolute /public/ reference found in the assets — check js/index.js still needs relativizing")
	}
	// _chroma/style.css is generated at runtime, not embedded in public/.
	if body, code, err := c.get("/public/_chroma/style.css"); err == nil && code == http.StatusOK {
		if err := writeOut(filepath.Join(dir, "public", "_chroma", "style.css"), body); err != nil {
			return err
		}
	}
	return c.writePages(dir)
}

func (c *Crawler) writePages(dir string) error {
	for _, u := range c.order {
		p := c.pages[u]
		if err := writeOut(filepath.Join(dir, filepath.FromSlash(p.File)), c.rewrite(p)); err != nil {
			return err
		}
	}
	return nil
}

// FileOf returns where a captured URL was written, relative to the output dir.
func (c *Crawler) FileOf(u string) (string, bool) {
	p, ok := c.pages[canonicalURL(u)]
	if !ok {
		return "", false
	}
	return p.File, true
}

// rewrite maps every absolute URL in a page to something that resolves from the
// page's own directory in the static tree.
func (c *Crawler) rewrite(p *pvPage) string {
	// Depth of the directory holding this page's index.html.
	depth := len(strings.Split(strings.Trim(path.Dir(p.File), "/"), "/"))
	up := strings.Repeat("../", depth)

	body := setNoindex(p.Body)
	body = pvAttrRe.ReplaceAllStringFunc(body, func(m string) string {
		sub := pvAttrRe.FindStringSubmatch(m)
		attr, raw := sub[1], sub[2]
		return fmt.Sprintf(`%s="%s"`, attr, html.EscapeString(c.mapURL(html.UnescapeString(raw), up)))
	})
	return pvCSSRe.ReplaceAllStringFunc(body, func(m string) string {
		sub := pvCSSRe.FindStringSubmatch(m)
		return "url(" + up + strings.TrimPrefix(sub[1], "/") + ")"
	})
}

// setNoindex makes a captured page unindexable. gnoweb's own layout emits
// `<meta name="robots" content="index, follow">` on every page, so this
// REPLACES that tag rather than adding a second one: two conflicting robots
// directives leave the outcome to each crawler's precedence rules.
func setNoindex(body string) string {
	if pvRobotsRe.MatchString(body) {
		return pvRobotsRe.ReplaceAllString(body, noindexTag)
	}
	if loc := pvHeadRe.FindStringIndex(body); loc != nil {
		return body[:loc[1]] + noindexTag + body[loc[1]:]
	}
	return noindexTag + body
}

// mapURL is the single place that decides where a link points in the snapshot.
func (c *Crawler) mapURL(raw, up string) string {
	if raw == "" || !strings.HasPrefix(raw, "/") || strings.HasPrefix(raw, "//") {
		return raw // fragment, relative, mailto:, external — leave alone
	}
	target, frag, _ := strings.Cut(raw, "#")
	if frag != "" {
		frag = "#" + frag
	}
	// Assets: served from the copied public/ tree; the ?v= cache-buster is kept
	// on the href and ignored by any static file server.
	if clean, query, _ := strings.Cut(target, "?"); strings.HasPrefix(clean, "/public/") {
		clean = path.Clean(clean) // gnoweb emits "/public//favicon.ico"
		u := up + strings.TrimPrefix(clean, "/")
		if query != "" {
			u += "?" + query
		}
		return u + frag
	}
	if target == "/" {
		return up + "index.html" + frag
	}
	if p, ok := c.pages[canonicalURL(target)]; ok {
		return up + path.Dir(p.File) + "/" + frag
	}
	return c.Live + target + frag
}

// --- helpers ---------------------------------------------------------------

// getRetry backs off on 429: gnoweb rate-limits some views per IP, and a crawl
// is exactly the traffic shape that limiter is there to stop.
func (c *Crawler) getRetry(p string) (string, int, error) {
	var body string
	var code int
	var err error
	for attempt := range 3 {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
		body, code, err = c.get(p)
		if err != nil || code != http.StatusTooManyRequests {
			return body, code, err
		}
	}
	return body, code, err
}

func (c *Crawler) get(p string) (string, int, error) {
	req, err := http.NewRequest(http.MethodGet, c.Base+p, nil)
	if err != nil {
		return "", 0, err
	}
	// gnoweb redirects "/" and a few legacy paths; capture what is served, not
	// where it points.
	client := &http.Client{
		Timeout:       30 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", 0, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	return string(b), resp.StatusCode, err
}

// pageLinks extracts the absolute in-site paths a page points at.
func pageLinks(body string) []string {
	seen := map[string]bool{}
	var out []string
	for _, m := range pvAttrRe.FindAllStringSubmatch(body, -1) {
		raw := html.UnescapeString(m[2])
		if !strings.HasPrefix(raw, "/") || strings.HasPrefix(raw, "//") || strings.HasPrefix(raw, "/public/") {
			continue
		}
		p, _, _ := strings.Cut(raw, "#")
		p = canonicalURL(p)
		if p == "" || seen[p] {
			continue
		}
		seen[p] = true
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

var unsafeSeg = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

// urlToFile maps a gnoweb path to a static file. The render page keeps its
// natural path (/r/x/y -> r/x/y/index.html); render arguments go under _a/ and
// the tab query under _t/, both slugged, so no path segment ever carries $, :
// or & — characters that survive a URL but not every static host.
//
//	/r/x/y:p/about$source  ->  r/x/y/_a/p-about/_t/source/index.html
func urlToFile(u string) string {
	base, args, query := splitGnowebURL(strings.TrimPrefix(u, "/"))
	// A trailing slash is gnoweb's listing view, a different page from the
	// render; give it its own file so the two can never overwrite each other.
	listing := strings.HasSuffix(base, "/") && base != "/"
	base = strings.Trim(base, "/")
	if base == "" {
		base = "_root"
	}
	parts := []string{base}
	if listing {
		parts = append(parts, "_dir")
	}
	if args != "" {
		parts = append(parts, "_a", slug(args))
	}
	if query != "" {
		parts = append(parts, "_t", slug(query))
	}
	return path.Join(append(parts, "index.html")...)
}

// maxSlugLen keeps a long render argument from producing a path the filesystem
// or the static host rejects.
const maxSlugLen = 64

// slug turns a tab query or a render argument into one safe path segment.
//
// Two things it must not do. It must not emit "." or ".." — gnoweb happily
// serves "/r/x/y:..", and path.Join would fold that onto r/x/y/index.html,
// silently overwriting the package's own render page. And it must not map two
// different URLs onto one file: ":p/a-b", ":p/a/b" and ":p/a&b" all reduce to
// "p-a-b" once the unsafe characters collapse. So anything that is not already
// a safe segment carries a short digest of the input it came from.
func slug(s string) string {
	out := strings.Trim(unsafeSeg.ReplaceAllString(s, "-"), "-.")
	if len(out) > maxSlugLen {
		out = out[:maxSlugLen]
	}
	if out == s && out != "" {
		return out
	}
	sum := sha256.Sum256([]byte(s))
	if out == "" {
		return hex.EncodeToString(sum[:4])
	}
	return out + "-" + hex.EncodeToString(sum[:4])
}

func writeOut(p, body string) error {
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, []byte(body), 0o644)
}

// copyAssets copies gnoweb's public/ into the snapshot, relativizing the
// absolute "/public/…" references that live *inside* the assets. js/index.js
// builds its dynamic import specifiers from a hardcoded "/public/js/controller-"
// prefix, which 404s from any mount point other than the site root; rewriting it
// to a path relative to the asset's own URL keeps the snapshot portable.
func copyAssets(src, dst string) (int, error) {
	rewrites := 0
	err := filepath.Walk(src, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		out := filepath.Join(dst, rel)
		if fi.IsDir() {
			return os.MkdirAll(out, 0o755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		switch filepath.Ext(p) {
		case ".js", ".css":
			// Depth of this asset inside public/, so "/public/" resolves back
			// to the copied tree from wherever the asset is loaded from.
			up := "./"
			if d := filepath.ToSlash(filepath.Dir(rel)); d != "." {
				up = strings.Repeat("../", len(strings.Split(d, "/")))
			}
			if n := strings.Count(string(b), "/public/"); n > 0 {
				rewrites += n
				b = []byte(strings.ReplaceAll(string(b), "/public/", up))
			}
		}
		if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
			return err
		}
		return os.WriteFile(out, b, 0o644)
	})
	return rewrites, err
}

// waitServing polls probe until gnoweb answers, the process exits, or the
// deadline passes. died carries the node's exit so a crash fails in seconds
// with the real reason instead of timing out minutes later on "not ready".
func waitServing(base, probe string, timeout time.Duration, died <-chan error) error {
	deadline := time.Now().Add(timeout)
	client := &http.Client{Timeout: 3 * time.Second}
	u, err := url.JoinPath(base, probe)
	if err != nil {
		return err
	}
	for time.Now().Before(deadline) {
		select {
		case err := <-died:
			return fmt.Errorf("gnodev exited before serving %s — see the gnodev log: %w", probe, err)
		default:
		}
		if resp, err := client.Get(u); err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("gnoweb not ready after %s", timeout)
}

func sortedStrings(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
