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

// maxSlugLen mirrors r/moul/blog/blog.gno.
const maxSlugLen = 64

// introFile is the one file in a content directory that is not a post: its
// body becomes the markdown above the index, pushed with SetIntro.
//
// It is also why "intro" is a reserved slug in the realm. The file name maps
// to a slug everywhere else, so without that reservation a post called intro
// and the header would both want intro.md, and whichever the tool decided to
// treat it as, the other would be unreachable.
const introFile = "intro.md"

// introKey mirrors r/moul/blog/blog.gno: the manifest row the intro occupies.
// '!' is not a legal slug character, so the row can never collide with a post.
const introKey = "!intro"

// postFile is a local post: its front matter plus its body.
type postFile struct {
	slug  string
	path  string // absolute, for error messages and previews
	title string
	date  string // YYYY-MM-DD
	tags  string // normalized, comma-separated
	body  string // normalized markdown, no front matter
	hash  string // sha256 of the canonical record
}

// isIntro reports whether this entry is the index header rather than a post.
func (p postFile) isIntro() bool { return p.slug == introKey }

// normalize makes a file's bytes match what will live on chain.
//
// It strips trailing newlines and nothing else. The realm stores exactly what
// the transaction carried, so anything trimmed here that is not trimmed there
// (or the reverse) makes the two hashes disagree and reports an up-to-date
// post as outdated forever.
func normalize(body string) string { return strings.TrimRight(body, "\n") }

func hashOf(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// record mirrors r/moul/blog/blog.gno: the canonical serialization a post
// hashes to. Both sides build it identically, which is what lets one
// Manifest() read decide whether a post needs a transaction at all.
func record(title, date, tags, body string) string {
	return title + "\n" + date + "\n" + tags + "\n" + body
}

// validSlug mirrors r/moul/blog/blog.gno.
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

// validDate mirrors r/moul/blog/blog.gno: exactly YYYY-MM-DD, because the
// realm orders posts by the lexical order of this field.
func validDate(date string) bool {
	if len(date) != 10 {
		return false
	}
	for i := 0; i < 10; i++ {
		c := date[i]
		if i == 4 || i == 7 {
			if c != '-' {
				return false
			}
			continue
		}
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// normalizeTags mirrors splitTags in r/moul/blog/blog.gno: trimmed,
// lowercased, deduplicated, empties dropped, joined with commas.
func normalizeTags(tags string) string {
	var out []string
	for _, t := range strings.Split(tags, ",") {
		t = strings.ToLower(strings.TrimSpace(t))
		if t == "" {
			continue
		}
		dup := false
		for _, seen := range out {
			if seen == t {
				dup = true
				break
			}
		}
		if !dup {
			out = append(out, t)
		}
	}
	return strings.Join(out, ",")
}

// parseFrontMatter splits a post file into its `key: value` header and its
// body. The header is delimited by a line of exactly "---" at the top of the
// file and a second one closing it.
//
// Deliberately not YAML: the four keys are scalars, and a YAML dependency
// would buy nothing but a way for a multi-line value to change the hash
// without changing the file.
func parseFrontMatter(raw string) (map[string]string, string, error) {
	lines := strings.Split(raw, "\n")
	if len(lines) == 0 || strings.TrimSpace(lines[0]) != "---" {
		return nil, "", fmt.Errorf("no front matter: the file must start with a line of exactly ---")
	}
	meta := map[string]string{}
	for i := 1; i < len(lines); i++ {
		line := lines[i]
		if strings.TrimSpace(line) == "---" {
			return meta, strings.Join(lines[i+1:], "\n"), nil
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		k, v, ok := strings.Cut(line, ":")
		if !ok {
			return nil, "", fmt.Errorf("front matter line %d is not `key: value`: %q", i+1, line)
		}
		meta[strings.ToLower(strings.TrimSpace(k))] = strings.TrimSpace(v)
	}
	return nil, "", fmt.Errorf("front matter is never closed: add a second --- line")
}

// loadPosts reads every *.md directly inside dir. The slug is the file name
// without its extension; intro.md is the index header instead. Sub-directories
// are ignored rather than flattened, because a flattening rule is one more
// thing to keep in step with the realm.
func loadPosts(dir string) ([]postFile, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", dir, err)
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}

	var out []postFile
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		path := filepath.Join(abs, e.Name())
		raw, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if bytes.ContainsRune(raw, '\r') {
			return nil, fmt.Errorf("%s: contains a carriage return; convert the file to LF line endings", e.Name())
		}

		if e.Name() == introFile {
			body := normalize(string(raw))
			out = append(out, postFile{slug: introKey, path: path, body: body, hash: hashOf(body)})
			continue
		}

		p, err := parsePost(strings.TrimSuffix(e.Name(), ".md"), path, string(raw))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", e.Name(), err)
		}
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].slug < out[j].slug })
	return out, nil
}

// parsePost validates one post and computes the hash the chain will agree
// with. Every check here also exists in the realm; the point of duplicating
// them is that this one runs before the gas is spent.
func parsePost(slug, path, raw string) (postFile, error) {
	if !validSlug(slug) {
		return postFile{}, fmt.Errorf("%q is not a valid slug (1-%d bytes of [a-z0-9._-])", slug, maxSlugLen)
	}
	if slug == "intro" {
		return postFile{}, fmt.Errorf("%q is reserved: intro.md is the index header, not a post", slug)
	}
	meta, body, err := parseFrontMatter(raw)
	if err != nil {
		return postFile{}, err
	}
	title := strings.TrimSpace(meta["title"])
	if title == "" {
		return postFile{}, fmt.Errorf("front matter has no `title:`")
	}
	date := meta["date"]
	if !validDate(date) {
		return postFile{}, fmt.Errorf("front matter `date:` must be YYYY-MM-DD, got %q", date)
	}
	tags := normalizeTags(meta["tags"])
	body = normalize(strings.TrimLeft(body, "\n"))
	if body == "" {
		return postFile{}, fmt.Errorf("the post has no body")
	}
	return postFile{
		slug:  slug,
		path:  path,
		title: title,
		date:  date,
		tags:  tags,
		body:  body,
		hash:  hashOf(record(title, date, tags, body)),
	}, nil
}
