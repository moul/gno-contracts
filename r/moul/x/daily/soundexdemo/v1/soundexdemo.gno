// Package soundexdemo is a small gnoweb demo of the Soundex phonetic algorithm
// provided by the [p/moul/x/daily/soundex](/p/moul/x/daily/soundex/v1) library:
// it groups a small name list by phonetic key so the "sounds alike" clusters
// are visible.
//
// It contains no phonetic logic of its own. Stateless, so Render is
// deterministic — names are grouped in first-seen order, never by iterating a
// map.
package soundexdemo

import (
	"strings"

	"gno.land/p/moul/x/daily/soundex/v1"
)

// names include several deliberate near-collisions.
var names = []string{
	"Robert", "Rupert", "Rubin",
	"Ashcraft", "Ashcroft",
	"Tymczak", "Pfister", "Honeyman",
}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the name table + clusters
//	Render("/<name>")              -> that name's key
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Soundex\n\n")
	b.WriteString("Phonetic keys for English names, demoing the ")
	b.WriteString("[`p/moul/x/daily/soundex`](/p/moul/x/daily/soundex/v1) library.\n\n")

	if q := parseArg(path); q != "" {
		k := soundex.Encode(q)
		b.WriteString("## `")
		b.WriteString(q)
		b.WriteString("`\n\n")
		if k == "" {
			b.WriteString("_No ASCII letters — no key._\n")
		} else {
			b.WriteString("key: **")
			b.WriteString(k)
			b.WriteString("** (normalized: `")
			b.WriteString(soundex.Normalize(q))
			b.WriteString("`)\n")
		}
		return b.String()
	}

	b.WriteString("| name | key |\n|---|---|\n")
	for _, n := range names {
		b.WriteString("| ")
		b.WriteString(n)
		b.WriteString(" | `")
		b.WriteString(soundex.Encode(n))
		b.WriteString("` |\n")
	}

	// group by key, preserving first-seen order (never iterate a map)
	b.WriteString("\n## Sounds alike\n\n")
	keys := []string{}
	byKey := map[string][]string{}
	for _, n := range names {
		k := soundex.Encode(n)
		if _, seen := byKey[k]; !seen {
			keys = append(keys, k)
		}
		byKey[k] = append(byKey[k], n)
	}
	for _, k := range keys {
		if len(byKey[k]) < 2 {
			continue
		}
		b.WriteString("- **")
		b.WriteString(k)
		b.WriteString("**: ")
		b.WriteString(strings.Join(byKey[k], ", "))
		b.WriteString("\n")
	}

	b.WriteString("\n> A *blocking* key for finding candidates, never proof that two names match.\n")
	return b.String()
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
