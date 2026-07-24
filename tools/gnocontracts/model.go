package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// manifestFile is the source of truth for the contract catalog, relative to the
// repository root.
const manifestFile = "contracts.json"

// Manifest is the top-level contracts.json document.
type Manifest struct {
	// Networks are the chains we track upload status against.
	Networks []Network `json:"networks"`
	// Contracts is the catalog, kept sorted by PkgPath.
	Contracts []Contract `json:"contracts"`
}

// Network identifies a gno chain.
type Network struct {
	Name    string `json:"name"`
	ChainID string `json:"chain_id"`
	RPC     string `json:"rpc"`
}

// Contract is one versioned package in the repository.
type Contract struct {
	PkgPath     string         `json:"pkgpath"`     // gno.land/r/moul/hello/v1
	Dir         string         `json:"dir"`         // r/moul/hello/v1
	Kind        string         `json:"kind"`        // "p" (pure) or "r" (realm)
	Name        string         `json:"name"`        // hello (may contain slashes)
	Version     string         `json:"version"`     // v1
	Description string         `json:"description"` // hand-authored; preserved across scans
	// Source is the provenance of an imported package: ideally the gno-contracts
	// PR that added it (so the PR holds the metadata/context), or the origin repo.
	// Hand-authored; preserved across scans; rendered into the package README.
	Source    string         `json:"source,omitempty"`
	Deps      []string       `json:"deps"`      // gno.land/* imports (non-test)
	Draft     bool           `json:"draft"`     // work-in-progress, excluded from publish
	Published map[string]Pub `json:"published"` // network name -> upload status
}

// Pub is the upload status of a contract on a given network.
type Pub struct {
	Uploaded  bool   `json:"uploaded"`
	Tx        string `json:"tx,omitempty"`
	CheckedAt string `json:"checked_at,omitempty"`
}

// defaultNetworks seeds a fresh manifest. Adjust RPC/chain-id as chains change.
func defaultNetworks() []Network {
	return []Network{
		{Name: "portal-loop", ChainID: "portal-loopz", RPC: "https://rpc.gno.land:443"},
		{Name: "test6", ChainID: "test6", RPC: "https://rpc.test6.testnets.gno.land:443"},
		{Name: "topaz", ChainID: "topaz-1", RPC: "https://rpc.topaz.testnets.gno.land:443"},
	}
}

// repoRoot returns the repository root: the nearest ancestor of the CWD that
// contains a gnowork.toml file.
func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if fileExists(filepath.Join(dir, "gnowork.toml")) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("gnowork.toml not found in %q or any parent", dir)
		}
		dir = parent
	}
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// loadManifest reads contracts.json, or returns a seeded manifest if absent.
func loadManifest(root string) (*Manifest, error) {
	p := filepath.Join(root, manifestFile)
	b, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return &Manifest{Networks: defaultNetworks()}, nil
	}
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("parse %s: %w", manifestFile, err)
	}
	if len(m.Networks) == 0 {
		m.Networks = defaultNetworks()
	}
	return &m, nil
}

// save writes the manifest back as pretty JSON with a trailing newline.
func (m *Manifest) save(root string) error {
	m.sort()
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return os.WriteFile(filepath.Join(root, manifestFile), b, 0o644)
}

func (m *Manifest) sort() {
	sort.Slice(m.Contracts, func(i, j int) bool {
		return m.Contracts[i].PkgPath < m.Contracts[j].PkgPath
	})
}

func (m *Manifest) byPkgPath() map[string]*Contract {
	out := make(map[string]*Contract, len(m.Contracts))
	for i := range m.Contracts {
		out[m.Contracts[i].PkgPath] = &m.Contracts[i]
	}
	return out
}

// scanContracts walks p/moul and r/moul under root and returns a Contract for
// every directory containing a gnomod.toml.
func scanContracts(root string) ([]Contract, error) {
	var out []Contract
	for _, base := range []string{"p/moul", "r/moul"} {
		bp := filepath.Join(root, base)
		if !fileExists(bp) {
			continue
		}
		err := filepath.Walk(bp, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() || info.Name() != "gnomod.toml" {
				return nil
			}
			module, err := parseModule(path)
			if err != nil {
				return err
			}
			dir := filepath.Dir(path)
			rel, err := filepath.Rel(root, dir)
			if err != nil {
				return err
			}
			c, err := deriveContract(module, filepath.ToSlash(rel), dir)
			if err != nil {
				return fmt.Errorf("%s: %w", rel, err)
			}
			out = append(out, c)
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return out, nil
}

// parseModule extracts the module path from a gnomod.toml file.
func parseModule(gnomodPath string) (string, error) {
	b, err := os.ReadFile(gnomodPath)
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "module") {
			// module = "gno.land/..."
			if i := strings.Index(line, "\""); i >= 0 {
				if j := strings.LastIndex(line, "\""); j > i {
					return line[i+1 : j], nil
				}
			}
		}
	}
	return "", fmt.Errorf("no module declaration in %s", gnomodPath)
}

// deriveContract builds a Contract from a module path such as
// "gno.land/r/moul/hello/v1" or "gno.land/p/moul/defi/amm/v2".
func deriveContract(module, dir, absDir string) (Contract, error) {
	parts := strings.Split(module, "/")
	// gno.land / (p|r) / moul / <name...> / vN
	if len(parts) < 5 || parts[0] != "gno.land" || parts[2] != "moul" {
		return Contract{}, fmt.Errorf("unexpected module path %q (want gno.land/{p,r}/moul/<name>/vN)", module)
	}
	kind := parts[1]
	if kind != "p" && kind != "r" {
		return Contract{}, fmt.Errorf("unexpected kind %q in %q", kind, module)
	}
	version := parts[len(parts)-1]
	if !isVersion(version) {
		return Contract{}, fmt.Errorf("module %q is not versioned (expected trailing /vN)", module)
	}
	name := strings.Join(parts[3:len(parts)-1], "/")
	deps, err := parseDeps(absDir)
	if err != nil {
		return Contract{}, err
	}
	return Contract{
		PkgPath: module,
		Dir:     dir,
		Kind:    kind,
		Name:    name,
		Version: version,
		Deps:    deps,
	}, nil
}

func isVersion(s string) bool {
	if len(s) < 2 || s[0] != 'v' {
		return false
	}
	for _, r := range s[1:] {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// parseDeps returns the sorted, de-duplicated set of gno.land/* imports found in
// the non-test .gno files of dir (runtime dependencies, used for publish order).
func parseDeps(dir string) ([]string, error) {
	return parseDepsMode(dir, false)
}

// parseDepsMode is parseDeps with control over test files. Vendoring must
// include test-only dependencies so `gno test` resolves them autonomously.
func parseDepsMode(dir string, includeTests bool) ([]string, error) {
	set := map[string]bool{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".gno") {
			continue
		}
		if !includeTests && strings.HasSuffix(e.Name(), "_test.gno") {
			continue
		}
		imps, err := parseImports(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		for _, imp := range imps {
			if strings.HasPrefix(imp, "gno.land/") {
				set[imp] = true
			}
		}
	}
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out, nil
}

// parseImports extracts imported package paths from a .gno source file. It
// handles both single and grouped import forms without a full parser.
func parseImports(file string) ([]string, error) {
	b, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var out []string
	lines := strings.Split(string(b), "\n")
	inBlock := false
	for _, line := range lines {
		t := strings.TrimSpace(line)
		switch {
		case inBlock:
			if t == ")" {
				inBlock = false
				continue
			}
			if p, ok := importPath(t); ok {
				out = append(out, p)
			}
		case strings.HasPrefix(t, "import ("):
			inBlock = true
		case strings.HasPrefix(t, "import "):
			if p, ok := importPath(strings.TrimPrefix(t, "import ")); ok {
				out = append(out, p)
			}
		}
	}
	return out, nil
}

// importPath extracts a quoted import path from a line, dropping any alias.
func importPath(s string) (string, bool) {
	i := strings.Index(s, "\"")
	if i < 0 {
		return "", false
	}
	j := strings.Index(s[i+1:], "\"")
	if j < 0 {
		return "", false
	}
	return s[i+1 : i+1+j], true
}
