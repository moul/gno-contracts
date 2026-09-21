package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// The packages slot is the one slot nobody should maintain by hand: it is a
// statement about what is deployed, and the answer changes every time a
// contract lands. contracts.json already tracks that, per network, so this
// reads it and emits the slot body.
//
// Only the fields used here are modelled; contracts.json carries more. Written
// by tools/gnocontracts (`manifest` / `status`), which is the authority on the
// shape: see tools/gnocontracts/model.go.
type catalog struct {
	Contracts []catalogEntry `json:"contracts"`
}

type catalogEntry struct {
	PkgPath   string `json:"pkgpath"`
	Kind      string `json:"kind"` // "p" (pure) or "r" (realm)
	Name      string `json:"name"` // may contain slashes: "x/daily/counter", "ulist/lplist"
	Version   string `json:"version"`
	Published map[string]struct {
		Uploaded bool `json:"uploaded"`
	} `json:"published"`
}

// experimentPrefix marks the daily-experiment tree. Those are a body of work to
// count, not a list to read: there are more of them than of everything else
// combined, and naming all of them would bury the libraries.
const experimentPrefix = "x/"

// catalogPath locates contracts.json at the repository root, the same way
// defaultContentDir locates the content directory.
func catalogPath() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "gnowork.toml")); err == nil {
			return filepath.Join(dir, "contracts.json"), nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no gnowork.toml above the working directory: pass -catalog")
		}
		dir = parent
	}
}

func loadCatalog(path string) (*catalog, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var c catalog
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(c.Contracts) == 0 {
		return nil, fmt.Errorf("%s: no contracts", path)
	}
	return &c, nil
}

// versionNum parses the numeric part of a "vN" version. An unversioned
// contract (r/moul/home itself, see AGENTS.md rule 1) reports -1, so it sorts
// below any real version and a family containing one still picks the vN.
func versionNum(v string) int {
	if len(v) < 2 || v[0] != 'v' {
		return -1
	}
	n, err := strconv.Atoi(v[1:])
	if err != nil {
		return -1
	}
	return n
}

// latestOnNetwork keeps, per family name, the highest version uploaded to the
// given network. Comparison is numeric so v10 beats v9, which a string sort
// gets backwards. Mirrors latestOwn in tools/gnocontracts/graph.go; the
// difference is that this one filters on deployment first, because the page
// claims what is live and not what is in the repository.
func latestOnNetwork(c *catalog, network string) []catalogEntry {
	best := map[string]catalogEntry{}
	for _, e := range c.Contracts {
		if !e.Published[network].Uploaded {
			continue
		}
		key := e.Kind + "/" + e.Name
		if cur, seen := best[key]; seen && versionNum(cur.Version) >= versionNum(e.Version) {
			continue
		}
		best[key] = e
	}
	out := make([]catalogEntry, 0, len(best))
	for _, e := range best {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// link renders one entry as a markdown link into gnoweb, labelled by the family
// name. The label keeps any nesting ("demo/hello", "ulist/lplist") and drops
// only the version: the href already pins the version, and trimming to the last
// segment would render r/moul/hello and r/moul/demo/hello as the same word.
func link(e catalogEntry) string {
	label := e.Name
	path := "/" + e.Kind + "/moul/" + e.Name
	if e.Version != "" {
		path += "/" + e.Version
	}
	return "[" + label + "](" + path + ")"
}

func joinLinks(es []catalogEntry) string {
	parts := make([]string, len(es))
	for i, e := range es {
		parts[i] = link(e)
	}
	return strings.Join(parts, " · ")
}

// renderPackages builds the body of the "packages" slot: the counts, which are
// the part that goes stale by itself, and the libraries and realms by name.
// Deterministic for a given catalog, so re-running it on an unchanged
// contracts.json produces a byte-identical slot and `gnohome status` stays
// quiet.
func renderPackages(c *catalog, network string) string {
	var libs, realms, experiments []catalogEntry
	for _, e := range latestOnNetwork(c, network) {
		switch {
		case strings.HasPrefix(e.Name, experimentPrefix):
			experiments = append(experiments, e)
		case e.Kind == "p":
			libs = append(libs, e)
		default:
			realms = append(realms, e)
		}
	}
	total := len(libs) + len(realms) + len(experiments)

	var expLibs int
	for _, e := range experiments {
		if e.Kind == "p" {
			expLibs++
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, "%d packages of mine are live on %s, from [moul/gno-contracts](https://github.com/moul/gno-contracts).\n", total, network)
	if len(libs) > 0 {
		fmt.Fprintf(&b, "\n**Libraries** (%d): %s\n", len(libs), joinLinks(libs))
	}
	if len(realms) > 0 {
		fmt.Fprintf(&b, "\n**Realms** (%d): %s\n", len(realms), joinLinks(realms))
	}
	if len(experiments) > 0 {
		fmt.Fprintf(&b, "\n**Daily experiments** (%d): one package a day, %s and %s under `x/daily`.\n",
			len(experiments), plural(expLibs, "library", "libraries"), plural(len(experiments)-expLibs, "realm", "realms"))
	}
	return strings.TrimRight(b.String(), "\n")
}

// plural keeps the generated prose readable when a count happens to be 1. The
// slot is a page a person reads, not a log line.
func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return strconv.Itoa(n) + " " + many
}
