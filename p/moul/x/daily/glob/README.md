# `gno.land/p/moul/x/daily/glob/v0`

**Shell-style pattern matching, with and without path awareness**: `Match`,
`MatchPath`, `Valid`, `Filter`, `FilterPath`, `Any`, `AnyPath`.

```go
import "gno.land/p/moul/x/daily/glob/v0"

glob.Match("*.gno", "a.gno")                     // true
glob.Match("g1[a-z0-9]*", "g1manfred")           // true
glob.MatchPath("gno.land/r/moul/*", "gno.land/r/moul/home")   // true
glob.MatchPath("gno.land/r/moul/*", "gno.land/r/moul/x/daily") // false, '*' stops at '/'
glob.MatchPath("gno.land/r/moul/**", "gno.land/r/moul/x/daily") // true

allow := []string{"gno.land/r/moul/home", "gno.land/r/moul/x/daily/**"}
glob.AnyPath(allow, "gno.land/r/moul/x/daily/globdemo") // true
glob.AnyPath(allow, "gno.land/r/moul/homeless")         // false
```

Live demo: [`r/moul/x/daily/globdemo`](/r/moul/x/daily/globdemo/v0).

## Why not `strings.HasPrefix`

Every realm that decides what a caller may touch eventually writes an
allowlist, and the first version of it is a prefix check. The prefix
`gno.land/r/moul/` also matches `gno.land/r/moulier/`, which is a different
namespace owned by a different person; the prefix `gno.land/r/moul/home` also
matches `gno.land/r/moul/homeless`. Registering a sibling name one byte longer
than an allowed one is cheap, and the check cannot tell the difference, because
a prefix has no idea where a path segment ends.

`MatchPath` makes the boundary part of the grammar rather than something the
caller remembered to append. `*`, `?` and a character class stay inside one
segment; only a `**` that is a whole segment crosses, and it crosses as many as
it needs, including zero (`a/**/b` matches `a/b`).

## The grammar

| | |
|---|---|
| `?` | any single byte |
| `*` | any run of bytes, including none |
| `[abc]` | any one of the listed bytes |
| `[a-z]` | any byte in the range, both ends included |
| `[!abc]` | any byte not listed; `[^abc]` is the same thing |
| `\x` | the literal byte `x`, for any `x` |
| `**` | in `MatchPath` only, and only as a whole segment: zero or more segments |

A `]` inside a class is written `\]`. There is no POSIX leading-`]` rule: one
way to say it beats two, and the one that survives also works for `-` and `\`.
A `-` at either end of a class is a literal dash, as POSIX has it.

## Three decisions worth knowing before you use it

- **An invalid pattern matches nothing.** `Match` has no error return, so the
  choice is between inert and permissive, and an allowlist entry with a typo
  that matches everything is the worse of the two. `Valid` is how a caller
  finds out, and it should be called at write time, not at match time. `Any`
  skips a bad entry and keeps evaluating the good ones, so one typo costs one
  rule rather than the whole list.
- **The matcher is a loop, not a recursion, and that is a security property.**
  The recursive formulation every glob tutorial shows branches at each `*` and
  is exponential in the number of them: `a*a*a*a*a*a*b` against two dozen `a`s
  is where it stops returning. This one walks forward and remembers a single
  backtrack point, the most recent star, which is
  `O(len(pattern) * len(name))` in time and constant in space. On chain the
  difference is not a slow page, it is a gas bomb a caller gets to aim, because
  the pattern is usually what the realm stored and the subject is usually what
  the caller supplied. There is no length cap for the same reason: the bound is
  a product of two lengths the caller already pays for.
- **It matches bytes, not runes.** `?` consumes one byte, so it takes two of
  them to cover a single `é`, and a class range compares byte values. That is
  fine for what this is for, package paths, bech32 addresses, handles and file
  names, all ASCII. It is **not** the package for matching prose, and a
  `[a-z]` class will not do what you want to a non-ASCII name.

## What it is not

Not a regular expression engine, and not a path cleaner: it compares the
strings it is handed. `a//b` has an empty segment and is not `a/b`, a trailing
`/` leaves a trailing empty segment, and `.` and `..` mean nothing. Normalise
before matching if your input can contain any of those.
