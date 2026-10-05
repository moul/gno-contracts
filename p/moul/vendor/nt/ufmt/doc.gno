// Package ufmt is a preview of gno.land/p/nt/ufmt/v2, published here before
// that path exists.
//
// This is v2 of ufmt. It is not yet published at its expected path,
// gno.land/p/nt/ufmt/v2. Until it is, import it from
// gno.land/p/moul/vendor/nt/ufmt/v2; once gno.land/p/nt/ufmt/v2 is live,
// switch the import and nothing else, because the API is meant to be the same.
// This path is then frozen and never updated again.
//
// v0 (gno.land/p/nt/ufmt/v0) supports a handful of verbs and no flags, so
// "%08x", "%X" and "%-10s" print "(unhandled)" or drop their padding without a
// word. v2 follows Go's fmt instead: the same flags, widths, precisions and
// verbs, and the same error strings in place of panics. Where it cannot follow
// Go, because gno has no reflect, it says so below.
//
// Supported, as in Go's fmt:
//
//	flags      '+' '-' '#' ' ' '0'
//	width      %8d, %*d, and a negative * width left-justifies
//	precision  %.2f, %.*f, %.3s (in runes)
//	indexes    %[2]d %[1]s, %[1]*[2]d
//	general    %v %+v %#v %T %%
//	bool       %t
//	integer    %b %c %d %o %O %q %x %X %U, every int and uint type
//	float      %b %e %E %f %F %g %G %x %X, float32 and float64
//	string     %s %q %x %X, and []byte the same way
//	errors     %w in Errorf, unwrapped by errors.Unwrap and errors.Is
//	methods    Formatter, GoStringer, error, Stringer, in Go's order
//	composite  []T of the basic types, []any, []error, and map[string]T
//	           with its keys sorted, as Go prints them
//
// Errors are written into the output, never panicked: "%!d(string=hi)" for a
// wrong type, "%!d(MISSING)" for a missing argument, "%!(EXTRA int=1)" for an
// unused one, "%!(NOVERB)" for a trailing '%'.
//
// What gno cannot do, and what v2 prints instead:
//
//   - no reflect, so a struct, a pointer, a named type without a String
//     method, or a slice or map of anything other than the types listed above
//     prints "(unhandled)", and %T names only the types it knows ("unknown"
//     otherwise). Give the type a String method.
//   - %p is not supported.
//
// What changed from v0, so a migration is a review and not a find-and-replace:
//
//   - Sprint adds a space only between two operands when neither is a string,
//     as Go does; v0 put a space between every pair.
//   - %v of a float, and Sprint of one, is the shortest representation ("3.14"),
//     as Go does; v0 printed "%f" ("3.140000") from Sprint.
//   - %e defaults to 6 digits after the point, as Go does; v0 used 2.
//   - %v of a []byte prints "[104 105]", as Go does; v0 wrote the raw bytes.
//     Use %s for the string.
//   - a missing or extra argument, or a trailing '%', is written into the
//     output instead of panicking.
//   - an error is preferred to a String method when a value has both.
package ufmt
