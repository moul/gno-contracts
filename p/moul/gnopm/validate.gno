package gnopm

import "strings"

// Size caps. Every string the chain stores is bounded: an unbounded field is an
// unbounded storage deposit, and on gno.land the deposit is paid per byte by
// whoever writes it.
const (
	MaxPkgPathLen = 256
	MaxRepoLen    = 512
	MaxDirLen     = 256
	MaxRefLen     = 255 // git's own limit for a single ref name

	// MaxClaimants bounds how many addresses may claim one package path.
	// Unbounded, it is a spam surface: one path with ten thousand claims is a
	// Render that never returns and a listing nobody can read.
	MaxClaimants = 16
)

// ValidCommit reports whether s is a git object id: 40 (SHA-1) or 64 (SHA-256)
// lowercase hex characters. Case is fixed so the same object always produces
// the same stored bytes, and so a verifier comparing two claims compares two
// comparable strings.
func ValidCommit(s string) bool {
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

// ValidRepo reports whether s is a repository URL this registry accepts.
//
// Deliberately narrow: "https://" only, a host, and a path. Not a taste
// judgement about git transports, a safety one. Whatever is stored here is
// eventually rendered as a link by this realm, by gnoweb and by every explorer
// that reads the registry, and the set of schemes that are safe to hand a
// browser is exactly one. "javascript:", "data:" and "file:" are the attack;
// "git://" and "ssh://" are merely unreachable from a web page, and a claimant
// who needs one can point at the https mirror every forge already serves.
func ValidRepo(s string) bool {
	if s == "" || len(s) > MaxRepoLen {
		return false
	}
	const scheme = "https://"
	if !strings.HasPrefix(s, scheme) {
		return false
	}
	rest := s[len(scheme):]
	if rest == "" || strings.HasPrefix(rest, "/") {
		return false
	}
	// A host must be present and must not be a userinfo trick
	// ("https://github.com@evil.example/x" fetches from evil.example while
	// reading as GitHub).
	slash := strings.IndexByte(rest, '/')
	host := rest
	if slash >= 0 {
		host = rest[:slash]
	}
	if host == "" || strings.ContainsAny(host, "@:") {
		return false
	}
	if !strings.Contains(host, ".") {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !urlByteOK(s[i]) {
			return false
		}
	}
	return !strings.Contains(s, "..")
}

// urlByteOK is an allowlist, not a denylist: the printable ASCII that appears
// in a real repository URL. Everything else, control characters and the bidi
// overrides in particular, is refused rather than escaped, because a field that
// can only hold safe bytes needs no escaping at any of its render sites.
func urlByteOK(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	switch c {
	case '-', '.', '_', '~', ':', '/', '%', '+':
		return true
	}
	return false
}

// ValidDir reports whether s names the subdirectory of the repository holding
// the package. Empty means the repository root, which is the common case for a
// single-package repo and must stay expressible.
func ValidDir(s string) bool {
	if s == "" {
		return true
	}
	if len(s) > MaxDirLen {
		return false
	}
	if strings.HasPrefix(s, "/") || strings.HasSuffix(s, "/") {
		return false
	}
	for _, p := range strings.Split(s, "/") {
		if p == "" || p == "." || p == ".." {
			return false
		}
		for i := 0; i < len(p); i++ {
			if !pathByteOK(p[i]) {
				return false
			}
		}
	}
	return true
}

func pathByteOK(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	switch c {
	case '-', '.', '_':
		return true
	}
	return false
}

// ValidRef reports whether s is a fully-qualified git ref, or empty.
//
// The ref is optional and is never the thing that is verified: a ref moves, a
// commit does not. It is recorded so a reader can tell a claim pinned to a
// released tag from one pinned to a commit on nobody's branch, and so a
// verifier can check the claimed commit is still reachable from it rather than
// dangling behind a force-push.
func ValidRef(s string) bool {
	if s == "" {
		return true
	}
	if len(s) > MaxRefLen || !strings.HasPrefix(s, "refs/") {
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
		if p == "" || p == "@" || strings.HasPrefix(p, ".") || strings.HasSuffix(p, ".lock") {
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

// refByteOK is an allowlist, and deliberately narrower than git's own rule.
//
// git rejects a handful of metacharacters and permits everything else, which
// leaves a ref free to contain a backtick, a pipe or a bracket. Every other
// field here is an allowlist precisely so that no consumer has to escape
// anything, and one denylist field would undo that for all of them: a ref
// carrying a pipe breaks out of a markdown table cell, and one carrying a
// backtick breaks out of the inline-code span a renderer wraps it in.
//
// The cost is refs nobody writes. What stays expressible is every ref anyone
// actually has: alphanumerics, and the four separators git tooling puts in a
// name.
func refByteOK(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	switch c {
	case '-', '.', '_', '/', '+':
		return true
	}
	return false
}
