package gnopm

import "strings"

// Parsing a gno package path far enough to know who owns it.
//
// A path is "<domain>/<kind>/<namespace>/<name...>", optionally ending in a
// "/vN" version element: "gno.land/p/moul/md/v1", "gno.land/r/sys/users",
// "gno.land/r/g1abc.../scratch/v0". The namespace is the third element and it
// is the whole reason this file exists: it decides whether a claim comes from
// the party that controls the path or from a stranger, which is the strongest
// signal the registry can offer about a claim it can never itself verify.

// SplitPkgPath breaks a package path into its domain, kind ("p" or "r"),
// namespace and the remainder. ok is false for anything that is not shaped like
// a publishable gno path.
func SplitPkgPath(s string) (domain, kind, ns, rest string, ok bool) {
	if !ValidPkgPath(s) {
		return "", "", "", "", false
	}
	parts := strings.Split(s, "/")
	return parts[0], parts[1], parts[2], strings.Join(parts[3:], "/"), true
}

// Namespace returns the owning namespace of a package path, or "" if the path
// is not one.
func Namespace(s string) string {
	_, _, ns, _, ok := SplitPkgPath(s)
	if !ok {
		return ""
	}
	return ns
}

// Version returns the trailing "vN" element of a package path, or "" when the
// path carries none. Absent is legal and is not an error: gnoweb serves
// gno.land/u/<name> by calling the realm at exactly /r/<name>/home, so that one
// path can never carry a version.
func Version(s string) string {
	parts := strings.Split(s, "/")
	if len(parts) < 4 {
		return ""
	}
	last := parts[len(parts)-1]
	if len(last) < 2 || last[0] != 'v' {
		return ""
	}
	for i := 1; i < len(last); i++ {
		if last[i] < '0' || last[i] > '9' {
			return ""
		}
	}
	return last
}

// ValidPkgPath reports whether s is shaped like a publishable gno package path.
//
// It does NOT say the path exists on any chain, and cannot: a realm has no way
// to ask whether some other path was ever deployed. That gap is the registry's
// central honesty problem and is documented on Registry.
func ValidPkgPath(s string) bool {
	if s == "" || len(s) > MaxPkgPathLen {
		return false
	}
	if strings.HasPrefix(s, "/") || strings.HasSuffix(s, "/") || strings.Contains(s, "//") {
		return false
	}
	parts := strings.Split(s, "/")
	if len(parts) < 4 {
		return false
	}
	// The domain, which is a host and so must carry a dot.
	if !strings.Contains(parts[0], ".") {
		return false
	}
	if parts[1] != "p" && parts[1] != "r" {
		return false
	}
	for _, p := range parts {
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

// AddressNamespace reports whether ns is shaped like a gno bech32 address, the
// namespace every account owns without registering anything. A caller still
// has to check it is the claimant's own address; this only says which of the
// two ownership rules applies.
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
