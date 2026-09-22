package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// maxSlugLen mirrors r/moul/home/home.gno.
const maxSlugLen = 64

// reservedSlugs mirrors r/moul/home/home.gno: names the realm computes at
// render time and refuses as slot names. The scan.* half mirrors
// r/moul/home/scan.gno's scanPlaceholders.
//
// Keeping this in step matters more than it looks: this is the only thing that
// refuses a reserved name BEFORE a transaction is signed. Miss one here and
// the realm still refuses it, on chain, after the gas is spent.
var reservedSlugs = map[string]bool{
	"chainid":    true,
	"height":     true,
	"owner":      true,
	"realm":      true,
	"rev":        true,
	"slots":      true,
	"scan":       true,
	"scan.realm": true,
	"scan.me":    true,
	"scan.block": true,
	"scan.links": true,
}

type slotFile struct {
	slug string
	path string // absolute, so an emitted "$(cat …)" works from any directory
	body string // normalized
	hash string // sha256 of body, hex
}

// normalize makes a file's bytes match what will live on chain, so the hash
// computed here equals the hash the realm computes.
//
// It strips trailing newlines and NOTHING else, because the emitted
// `-args "$(cat file)"` has to reproduce it byte for byte: command
// substitution eats trailing newlines, so a body that kept one would hash
// differently on chain and the slot would report as outdated forever. It eats
// nothing else, which is why trailing spaces are kept: stripping them here
// would reintroduce exactly that mismatch in the other direction.
//
// Carriage returns are rejected rather than folded, for the same reason: `cat`
// would send them and folding them here would make the hashes disagree. See
// loadSlots.
func normalize(body string) string {
	return strings.TrimRight(body, "\n")
}

func hashOf(body string) string {
	sum := sha256.Sum256([]byte(body))
	return hex.EncodeToString(sum[:])
}

// validSlug mirrors r/moul/home/home.gno.
func validSlug(slug string) bool {
	if len(slug) == 0 || len(slug) > maxSlugLen {
		return false
	}
	for i := 0; i < len(slug); i++ {
		c := slug[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '-', c == '_', c == '.':
		default:
			return false
		}
	}
	return true
}

// loadSlots reads every *.md directly inside dir. The slug is the file name
// without its extension. Sub-directories are ignored rather than flattened,
// because a flattening rule is one more thing to keep in sync with the realm.
func loadSlots(dir string) ([]slotFile, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", dir, err)
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}

	var out []slotFile
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		slug := strings.TrimSuffix(e.Name(), ".md")
		if !validSlug(slug) {
			return nil, fmt.Errorf("%s: %q is not a valid slug (1-%d bytes of [a-z0-9._-])", e.Name(), slug, maxSlugLen)
		}
		if reservedSlugs[slug] {
			return nil, fmt.Errorf("%s: %q is reserved, the realm computes it at render time", e.Name(), slug)
		}
		path := filepath.Join(abs, e.Name())
		raw, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if bytes.ContainsRune(raw, '\r') {
			return nil, fmt.Errorf("%s: contains a carriage return; convert the file to LF line endings "+
				"(CRLF cannot round-trip through the emitted \"$(/bin/cat …)\")", e.Name())
		}
		body := normalize(string(raw))
		out = append(out, slotFile{slug: slug, path: path, body: body, hash: hashOf(body)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].slug < out[j].slug })
	return out, nil
}
