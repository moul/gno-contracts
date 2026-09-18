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

// ValidRepoID reports whether s is "<namespace>/<name>". The name is always a
// lowercase slug; the namespace is either a slug (a claimed user name) or a
// bech32 address (the caller's own). The two shapes cannot collide: an address
// is 40 characters and a slug caps at MaxRepoPartLen, which is 39.
//
// This layer validates the SHAPE only. Whether the caller may claim a given
// namespace is an ownership question that needs a chain, so it belongs to the
// realm (see the realm's README).
func ValidRepoID(s string) bool {
	ns, name, ok := SplitRepoID(s)
	if !ok {
		return false
	}
	return (validSlug(ns) || AddressNamespace(ns)) && validSlug(name)
}

// SplitRepoID splits "<namespace>/<name>" into its two halves. It does not
// validate either half; ok is false only when the id is not two slash-separated
// non-empty parts.
func SplitRepoID(s string) (ns, name string, ok bool) {
	i := strings.Index(s, "/")
	if i <= 0 || i == len(s)-1 || strings.Count(s, "/") != 1 {
		return "", "", false
	}
	return s[:i], s[i+1:], true
}

// AddressNamespace reports whether ns is shaped like a gno bech32 address, the
// namespace every account owns without registering anything. The realm still
// checks that it is the CALLER's address; this only says which of the two
// ownership rules applies.
func AddressNamespace(ns string) bool {
	if len(ns) != 40 || !strings.HasPrefix(ns, "g1") {
		return false
	}
	for i := 2; i < len(ns); i++ {
		if !strings.ContainsRune(bech32Charset, rune(ns[i])) {
			return false
		}
	}
	return true
}

// bech32Charset is bech32's data alphabet: lowercase alphanumerics minus the
// four characters it drops to avoid transcription errors (1, b, i, o).
const bech32Charset = "023456789acdefghjklmnpqrstuvwxyz"

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
