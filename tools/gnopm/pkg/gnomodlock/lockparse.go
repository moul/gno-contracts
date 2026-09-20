package gnomodlock

import (
	"fmt"
	"strconv"
	"strings"
)

// Parse reads the canonical gnomod.lock form.
//
// Hand-rolled rather than pulling in a TOML library, for the same reason the
// rest of this repository's tooling is: gno-contracts has no third-party Go
// dependencies, and the lock is a machine-written file in a fixed shape. The
// parser is deliberately strict, it reports the line number and refuses
// anything it does not recognise, rather than silently ignoring a key and
// producing a lock that means something other than what is written.
func Parse(s string) (*Lock, error) {
	l := &Lock{}
	var cur *LockEntry
	// flush appends the entry under construction.
	flush := func() error {
		if cur == nil {
			return nil
		}
		if cur.Module == "" {
			return fmt.Errorf("[[module]] block with no module key")
		}
		if err := cur.Source.Validate(); err != nil {
			return fmt.Errorf("module %q: %w", cur.Module, err)
		}
		if cur.Source.InTree() && cur.Hash != "" {
			return fmt.Errorf("module %q: a { dir } source must not carry a hash", cur.Module)
		}
		if !cur.Source.InTree() && cur.Hash == "" {
			return fmt.Errorf("module %q: a materialized source must carry a hash", cur.Module)
		}
		l.Modules = append(l.Modules, *cur)
		cur = nil
		return nil
	}

	for i, raw := range strings.Split(s, "\n") {
		ln := i + 1
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "[[module]]" {
			if err := flush(); err != nil {
				return nil, fmt.Errorf("line %d: %w", ln, err)
			}
			cur = &LockEntry{}
			continue
		}
		key, val, ok := SplitKV(line)
		if !ok {
			return nil, fmt.Errorf("line %d: cannot parse %q", ln, line)
		}
		if cur == nil {
			// Top-level keys, before the first [[module]].
			if key != "lock" {
				return nil, fmt.Errorf("line %d: unknown top-level key %q", ln, key)
			}
			n, err := strconv.Atoi(strings.TrimSpace(val))
			if err != nil {
				return nil, fmt.Errorf("line %d: lock version %q is not a number", ln, val)
			}
			if n != FormatVersion {
				return nil, fmt.Errorf("line %d: lock format %d, this gnopm understands %d, upgrade gnopm", ln, n, FormatVersion)
			}
			l.Format = n
			continue
		}
		switch key {
		case "module":
			v, err := Unquote(val)
			if err != nil {
				return nil, fmt.Errorf("line %d: module: %w", ln, err)
			}
			cur.Module = v
		case "hash":
			v, err := Unquote(val)
			if err != nil {
				return nil, fmt.Errorf("line %d: hash: %w", ln, err)
			}
			cur.Hash = v
		case "source":
			src, err := parseInlineSource(val)
			if err != nil {
				return nil, fmt.Errorf("line %d: source: %w", ln, err)
			}
			cur.Source = src
		default:
			return nil, fmt.Errorf("line %d: unknown key %q in [[module]]", ln, key)
		}
	}
	if err := flush(); err != nil {
		return nil, err
	}
	if l.Format == 0 {
		return nil, fmt.Errorf("no `lock = N` format declaration")
	}
	if _, err := l.ByModule(); err != nil {
		return nil, err
	}
	l.Sort()
	return l, nil
}

// splitKV splits `key = value` on the first `=`.
func SplitKV(line string) (key, val string, ok bool) {
	i := strings.Index(line, "=")
	if i < 0 {
		return "", "", false
	}
	key = strings.TrimSpace(line[:i])
	val = strings.TrimSpace(line[i+1:])
	if key == "" || val == "" {
		return "", "", false
	}
	return key, val, true
}

// parseInlineSource parses `{ commit = "…", dir = "…" }`.
func parseInlineSource(val string) (Source, error) {
	var s Source
	val = strings.TrimSpace(val)
	if !strings.HasPrefix(val, "{") || !strings.HasSuffix(val, "}") {
		return s, fmt.Errorf("expected an inline table, got %q", val)
	}
	body := strings.TrimSpace(val[1 : len(val)-1])
	if body == "" {
		return s, fmt.Errorf("empty inline table")
	}
	for _, field := range splitFields(body) {
		k, v, ok := SplitKV(strings.TrimSpace(field))
		if !ok {
			return s, fmt.Errorf("cannot parse field %q", field)
		}
		uv, err := Unquote(v)
		if err != nil {
			return s, fmt.Errorf("%s: %w", k, err)
		}
		switch k {
		case "dir":
			s.Dir = uv
		case "commit":
			s.Commit = uv
		case "repo":
			s.Repo = uv
		case "chain":
			s.Chain = uv
		case "tx":
			s.Tx = uv
		default:
			return s, fmt.Errorf("unknown field %q", k)
		}
	}
	return s, nil
}

// splitFields splits an inline-table body on commas. Values are quoted strings
// that never contain a comma in this format (module paths, hex commits, slash
// separated dirs), so a plain split is correct and a quote-aware scanner would
// be pretending to handle input the writer cannot produce.
func splitFields(body string) []string { return strings.Split(body, ",") }

func Unquote(v string) (string, error) {
	v = strings.TrimSpace(v)
	if len(v) < 2 || v[0] != '"' || v[len(v)-1] != '"' {
		return "", fmt.Errorf("expected a quoted string, got %q", v)
	}
	out, err := strconv.Unquote(v)
	if err != nil {
		return "", fmt.Errorf("bad string %q: %w", v, err)
	}
	return out, nil
}
