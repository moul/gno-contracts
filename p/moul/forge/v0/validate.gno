package forge

import "strings"

// Size caps. Every string the chain stores is bounded: an unbounded field is an
// unbounded storage deposit, and on gno.land the deposit is paid per byte by
// whoever writes it (100ugnot/byte at the time of writing).
const (
	MaxRepoPartLen = 39   // per side of "<namespace>/<name>"
	MaxRefNameLen  = 255  // git's own limit for a single ref name
	MaxTitleLen    = 200  // issue / change title
	MaxBodyLen     = 8192 // issue / change body
	MaxCommentLen  = 4096
	MaxDescLen     = 512
	MaxNoteLen     = 140 // single-line note attached to a log entry
	MaxMirrorLen   = 512
	MaxMirrors     = 8
	MaxLabels      = 10
	MaxLabelLen    = 32
)

// ValidOID reports whether s is a git object id: 40 (SHA-1) or 64 (SHA-256)
// lowercase hex characters. Case is fixed so the same object always has the
// same on-chain key and the same digest-chain input.
func ValidOID(s string) bool {
	if len(s) != 40 && len(s) != 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

// ValidRefName reports whether s is a fully-qualified ref name this forge
// accepts: a "refs/"-rooted subset of git-check-ref-format(1).
//
// Deliberately stricter than git: the name must be fully qualified, so there is
// never an ambiguity between "main" the branch and "main" the tag, and a client
// can map an on-chain name onto a local ref without a lookup table.
func ValidRefName(s string) bool {
	if s == "" || len(s) > MaxRefNameLen {
		return false
	}
	if !strings.HasPrefix(s, "refs/") {
		return false
	}
	if strings.Contains(s, "..") || strings.Contains(s, "@{") {
		return false
	}
	if strings.HasSuffix(s, "/") || strings.HasSuffix(s, ".") {
		return false
	}
	parts := strings.Split(s, "/")
	if len(parts) < 2 {
		return false
	}
	for _, p := range parts {
		if p == "" || p == "@" {
			return false
		}
		if strings.HasPrefix(p, ".") || strings.HasSuffix(p, ".lock") {
			return false
		}
		for i := 0; i < len(p); i++ {
			if !refByteOK(p[i]) {
				return false
			}
		}
	}
	return true
}

// refByteOK rejects the bytes git itself rejects in a ref component: ASCII
// control characters, space, DEL, and the pathspec/revision metacharacters.
func refByteOK(c byte) bool {
	if c <= 0x20 || c == 0x7f {
		return false
	}
	switch c {
	case '~', '^', ':', '?', '*', '[', '\\':
		return false
	}
	return true
}

// ValidRepoID reports whether s is "<namespace>/<name>", each side a lowercase
// slug. Namespaces are flat and first-come-first-served at this layer; a realm
// may bind them to an on-chain user registry on top (see the realm's README).
func ValidRepoID(s string) bool {
	i := strings.Index(s, "/")
	if i < 0 || strings.Count(s, "/") != 1 {
		return false
	}
	return validSlug(s[:i]) && validSlug(s[i+1:])
}

// validSlug: 1..MaxRepoPartLen chars, [a-z0-9] at both ends, [a-z0-9-_.] inside,
// no "..", no "--". Mixed case is rejected rather than folded: two ids that
// differ only in case would be two avl keys and one human-visible name.
func validSlug(s string) bool {
	if s == "" || len(s) > MaxRepoPartLen {
		return false
	}
	if !alnum(s[0]) || !alnum(s[len(s)-1]) {
		return false
	}
	if strings.Contains(s, "..") || strings.Contains(s, "--") {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if alnum(c) || c == '-' || c == '_' || c == '.' {
			continue
		}
		return false
	}
	return true
}

func alnum(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
}

// ValidText reports whether s fits in max bytes and carries no control
// characters other than newline and tab. Render output is markdown served by
// gnoweb, so a stray control byte is a rendering bug for every reader forever.
func ValidText(s string, max int) bool {
	if len(s) > max {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '\n' || c == '\t' {
			continue
		}
		if c < 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}

// ValidLine reports whether s is single-line text within max bytes. Used for
// titles and for log-entry notes, which are fields of the digest chain: a
// newline there would let one note impersonate two.
func ValidLine(s string, max int) bool {
	if strings.ContainsAny(s, "\n\t") {
		return false
	}
	return ValidText(s, max)
}

// ValidMirror reports whether s looks like a fetch locator. The chain does not
// resolve it: it only records where the maintainers say the objects are: so
// the check is a shape check, not a promise that anything is reachable.
func ValidMirror(s string) bool {
	if !ValidLine(s, MaxMirrorLen) || s == "" {
		return false
	}
	for _, p := range []string{"https://", "http://", "git://", "ssh://", "ipfs://", "ipns://", "ar://", "rad://", "git@"} {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

// ValidLabel reports whether s is an issue label.
func ValidLabel(s string) bool {
	return s != "" && ValidLine(s, MaxLabelLen) && !strings.Contains(s, ",")
}
