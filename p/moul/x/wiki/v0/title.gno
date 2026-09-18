package wiki

import (
	"errors"
	"strings"
	"unicode"

	"gno.land/p/nt/markdown/sanitize/v0"
)

// Namespace partitions the title space the way MediaWiki does: the same name
// can exist once per namespace, and each namespace gets its own rendering and
// its own listing.
type Namespace uint8

// There is deliberately no Talk namespace. Discussion is not an article with
// a prefix: it is an append-only thread attached to a page, which threads
// properly, moderates per message, and cannot be silently rewritten by whoever
// edits last. See talk.gno.
const (
	NSMain     Namespace = iota // articles
	NSUser                      // per-address pages
	NSCategory                  // category descriptions; membership is an index
	NSTemplate                  // reusable fragments
	NSHelp                      // documentation about the wiki itself
	NSSpecial                   // generated listings; never stored
)

// namespaces is the canonical table. The two-character code is the avl key
// prefix: it is fixed-width on purpose, because ufmt in gno supports no width
// or padding flags (ufmt.Sprintf("%02d", 7) returns "7"), so a numeric key
// would sort "0","1","10","2" and silently interleave namespaces past nine.
var namespaces = [...]struct {
	prefix string // canonical display prefix, "" for main
	code   string // fixed-width avl key prefix
}{
	NSMain:     {"", "00"},
	NSUser:     {"User", "01"},
	NSCategory: {"Category", "02"},
	NSTemplate: {"Template", "03"},
	NSHelp:     {"Help", "04"},
	NSSpecial:  {"Special", "05"},
}

// Title is a normalized (namespace, name) pair. The zero Title is invalid;
// build one with ParseTitle.
type Title struct {
	NS   Namespace
	Name string
}

// MaxTitleLen bounds a title name in bytes, matching MediaWiki's limit.
const MaxTitleLen = 255

var (
	ErrEmptyTitle   = errors.New("wiki: empty title")
	ErrTitleTooLong = errors.New("wiki: title too long")
	ErrTitleChar    = errors.New("wiki: illegal character in title")
)

// ParseTitle normalizes a user-supplied title.
//
// The normalization is a deliberate subset of MediaWiki's: underscores become
// spaces, runs of whitespace collapse, the first letter is upper-cased, and a
// recognized "Namespace:" prefix (case-insensitive) selects the namespace.
// "Talk:gno  land" and "talk:Gno_land" both parse to Talk:Gno land.
//
// The accepted character set is narrower than MediaWiki's on purpose. A title
// is rendered inside markdown and inside a URL path, so anything that is
// markdown-significant ("*", "`", "[", "|", "#", "<"), path-significant ("/",
// "?", "%", "&") or invisible (bidi and zero-width controls) is rejected
// rather than escaped. Rejecting keeps Title.String, Title.Slug and the
// sanitized render byte-identical, which is what TestTitleCharsSurviveSanitize
// pins.
func ParseTitle(raw string) (Title, error) {
	s := sanitize.StripBidiAndZeroWidth(raw)
	s = strings.ReplaceAll(s, "_", " ")
	s = strings.Join(strings.Fields(s), " ")
	if s == "" {
		return Title{}, ErrEmptyTitle
	}

	ns := NSMain
	if i := strings.Index(s, ":"); i > 0 {
		if n, ok := namespaceByPrefix(s[:i]); ok {
			ns = n
			s = strings.TrimSpace(s[i+1:])
			if s == "" {
				return Title{}, ErrEmptyTitle
			}
		}
	}

	if len(s) > MaxTitleLen {
		return Title{}, ErrTitleTooLong
	}
	for _, r := range s {
		if !validTitleRune(r) {
			return Title{}, ErrTitleChar
		}
	}
	return Title{NS: ns, Name: upperFirst(s)}, nil
}

// MustParseTitle is ParseTitle for titles known at development time.
func MustParseTitle(raw string) Title {
	t, err := ParseTitle(raw)
	if err != nil {
		panic(err)
	}
	return t
}

func namespaceByPrefix(p string) (Namespace, bool) {
	p = strings.TrimSpace(p)
	for i, e := range namespaces {
		if e.prefix != "" && strings.EqualFold(e.prefix, p) {
			return Namespace(i), true
		}
	}
	return NSMain, false
}

// validTitleRune reports whether r may appear in a title name. ASCII is an
// explicit allowlist; above ASCII only letters and digits are accepted, which
// admits "Élysée" and "東京" while excluding every invisible control.
func validTitleRune(r rune) bool {
	switch {
	case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		return true
	case r == ' ' || r == '-' || r == '.' || r == ',' || r == '\'' || r == '(' || r == ')' || r == ':':
		return true
	case r < 0x80:
		return false
	default:
		return unicode.IsLetter(r) || unicode.IsDigit(r)
	}
}

func upperFirst(s string) string {
	rs := []rune(s)
	if len(rs) == 0 {
		return s
	}
	rs[0] = unicode.ToUpper(rs[0])
	return string(rs)
}

// String is the canonical display form, "Talk:Gno land".
func (t Title) String() string {
	if t.NS == NSMain {
		return t.Name
	}
	return namespaces[t.NS].prefix + ":" + t.Name
}

// Slug is the URL form used in render paths, "Talk:Gno_land". Titles cannot
// contain "/", so a slug is always exactly one path segment and the segment
// after it is unambiguously a sub-route.
func (t Title) Slug() string {
	return strings.ReplaceAll(t.String(), " ", "_")
}

// Key is the avl key: a fixed-width namespace code followed by the name, so
// iteration yields main-namespace articles first, then Talk, and so on, each
// group in name order.
func (t Title) Key() string {
	return namespaces[t.NS].code + ":" + t.Name
}

// Prefix returns the avl key prefix that selects a whole namespace.
func (ns Namespace) Prefix() string { return namespaces[ns].code + ":" }

// String returns the namespace's display prefix, "" for the main namespace.
func (ns Namespace) String() string { return namespaces[ns].prefix }
