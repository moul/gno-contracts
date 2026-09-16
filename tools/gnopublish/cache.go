package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/gnolang/gno/gnovm/pkg/gnolang"
)

// cacheDir is where confirmed on-chain state is remembered between runs,
// relative to the repo root. Gitignored; `make clean` removes it.
const cacheDir = ".cache/gnopublish"

// cacheEntry records a package that a query CONFIRMED is on chain.
//
// Only positive results are cached. A package path on gno.land is immutable once
// deployed, so "on chain" stays true for the life of the chain — whereas
// "missing" can flip at any moment (another publisher, or a mainnet
// MsgAddPackage clearing the approvals queue), so it is always re-queried. A
// successful broadcast is NOT cached either: on mainnet that tx may only be
// parked, not live.
type cacheEntry struct {
	// Hash is the sha256 of the LOCAL production files at the moment the
	// on-chain content was verified identical to them (only set by -full).
	// Empty means existence was confirmed but content was not compared.
	Hash      string `json:"hash,omitempty"`
	CheckedAt string `json:"checked_at"`
}

// describe renders an entry for the status column, e.g.
// "(cached 2026-09-16, sha256:3f2a9c1be047)".
func (e cacheEntry) describe(cached bool) string {
	parts := []string{}
	if cached {
		day := e.CheckedAt
		if len(day) >= 10 {
			day = day[:10]
		}
		parts = append(parts, "cached "+day)
	}
	if e.Hash != "" {
		parts = append(parts, "sha256:"+shortHash(e.Hash))
	}
	return "(" + strings.Join(parts, ", ") + ")"
}

// chainCache is the on-disk cache for one network.
type chainCache struct {
	path    string
	disable bool
	Network string                `json:"network"`
	ChainID string                `json:"chain_id"`
	RPC     string                `json:"rpc"`
	Entries map[string]cacheEntry `json:"entries"`
	dirty   bool
}

// loadCache opens the cache for net. A missing or unreadable file, or one
// recorded for a different chain id, starts empty — the cache can only save
// queries, never assert something false.
func loadCache(root string, net network, disable bool) *chainCache {
	name := sanitize(net.Name) + "--" + sanitize(net.ChainID) + ".json"
	c := &chainCache{
		path:    filepath.Join(root, cacheDir, name),
		disable: disable,
		Network: net.Name,
		ChainID: net.ChainID,
		RPC:     net.RPC,
		Entries: map[string]cacheEntry{},
	}
	if disable {
		return c
	}
	b, err := os.ReadFile(c.path)
	if err != nil {
		return c
	}
	var onDisk chainCache
	if json.Unmarshal(b, &onDisk) != nil || onDisk.ChainID != net.ChainID || onDisk.Entries == nil {
		return c
	}
	c.Entries = onDisk.Entries
	return c
}

// onChain reports whether pkgpath is known to exist on chain.
func (c *chainCache) onChain(pkgpath string) (cacheEntry, bool) {
	if c.disable {
		return cacheEntry{}, false
	}
	e, ok := c.Entries[pkgpath]
	return e, ok
}

// contentVerified reports whether pkgpath was verified identical to local
// content whose hash is still hash.
func (c *chainCache) contentVerified(pkgpath, hash string) bool {
	e, ok := c.onChain(pkgpath)
	return ok && hash != "" && e.Hash == hash
}

// record remembers a confirmed on-chain package. hash is empty when only
// existence was checked; an existing verified hash is never downgraded by a
// later existence-only check.
func (c *chainCache) record(pkgpath, hash string) {
	if c.disable {
		return
	}
	if prev, ok := c.Entries[pkgpath]; ok && (hash == "" || prev.Hash == hash) {
		return // already known; an existence-only check never downgrades a hash
	}
	c.Entries[pkgpath] = cacheEntry{Hash: hash, CheckedAt: time.Now().UTC().Format(time.RFC3339)}
	c.dirty = true
}

// forgetHash drops a stale content verification (local files changed, or the
// on-chain content was found to differ) while keeping the existence fact.
func (c *chainCache) forgetHash(pkgpath string) {
	if e, ok := c.Entries[pkgpath]; ok && e.Hash != "" {
		e.Hash = ""
		c.Entries[pkgpath] = e
		c.dirty = true
	}
}

// save writes the cache atomically, only when something changed.
func (c *chainCache) save() error {
	if c.disable || !c.dirty {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(c.path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := c.path + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, c.path); err != nil {
		return err
	}
	c.dirty = false
	return nil
}

// localHash is a stable sha256 over the production files that would be
// uploaded: sorted by name, each as "name\x00body\x00". Test files are excluded,
// matching what reaches the chain.
func localHash(absDir, pkgpath string) (string, error) {
	mp, err := gnolang.ReadMemPackage(absDir, pkgpath, gnolang.MPUserProd)
	if err != nil {
		return "", err
	}
	files := append(mp.Files[:0:0], mp.Files...)
	sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })
	h := sha256.New()
	for _, f := range files {
		h.Write([]byte(f.Name))
		h.Write([]byte{0})
		h.Write([]byte(f.Body))
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// shortHash renders a hash for status output.
func shortHash(h string) string {
	if len(h) > 12 {
		return h[:12]
	}
	return h
}

func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_', r == '.':
			return r
		}
		return '_'
	}, s)
}
