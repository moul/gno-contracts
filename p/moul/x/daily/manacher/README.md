# `gno.land/p/moul/x/daily/manacher/v0`

**Manacher's algorithm**: every palindromic substring of a string, in one
linear pass. `Radii`, `Longest`, `LongestString`, `Count`, `Spans`,
`IsPalindrome`, `MaxInput`.

```go
import "gno.land/p/moul/x/daily/manacher/v0"

manacher.LongestString("banana")   // "anana"
manacher.Longest("babad")          // 0, 3  (leftmost of two length-3 ties)
manacher.Count("aaa")              // 6
manacher.Spans("banana", 3)        // [{1 3} {1 5} {3 3}]
manacher.Radii("banana")           // [0 1 0 1 0 3 0 5 0 3 0 1 0]
```

Expanding around every centre is the obvious way to find palindromes and it is
O(n²): a run of one byte re-walks the string from each position, so
`"aaaa...a"` is the input that kills it, and it is also the cheapest string in
the world to send. Manacher keeps the rightmost palindrome found so far and
reads the radius of each new centre off its mirror inside that window, so no
byte is ever compared twice. **O(n), with no bad case.**

Three things worth knowing, each with a test:

- **The separator is not reserved, and that is not an oversight.** Odd and even
  lengths are two problems (`aba` has a middle byte, `abba` does not), and the
  standard fix is to interleave a separator so every palindrome becomes an odd
  one around a single index. The usual worry is what happens when the input
  contains the separator byte. Nothing: separators land on even indices and the
  original bytes on odd ones, and the two positions the scan compares sum to
  twice the centre, so they always share a parity. `LongestString("#####")` is
  `"#####"`.
- **`Radii` is the primitive and the rest are one line each.** Entry `i` is the
  length of the longest palindrome centred there, so the substring is
  `s[(i-r)/2 : (i+r)/2]`. Even `i` is a centre between two bytes, odd `i` is a
  centre on one. Because the centre is recoverable as `2*Start+Length`, no two
  entries can describe the same substring.
- **Offsets are BYTE offsets**, not runes. gno strings are UTF-8, a reversed
  multi-byte rune is a different byte sequence, and `"été"` is therefore not a
  byte palindrome even though it reads as one. That is the right unit for
  slicing, and a caller doing rune arithmetic converts.

`Count` counts by position rather than by distinct text: `"aaa"` is 6, because
the three single bytes and the two pairs are different substrings that happen
to read alike. It is pinned against a quadratic brute-force scan over every
substring.

`MaxInput` is 4096, the one allocation a caller has to reason about: the
working array is 2n+1 ints. Past it the functions refuse rather than truncate.

**Live demo:** [`r/moul/x/daily/manacherdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/manacherdemo)
· render it at [`/r/moul/x/daily/manacherdemo/v0`](https://gno.land/r/moul/x/daily/manacherdemo/v0).
