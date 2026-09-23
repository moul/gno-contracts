# `gno.land/r/moul/x/allinone/textlab`

Every string algorithm in `p/moul` over one input at once, so they can be
compared instead of read about one at a time.

```
/r/moul/x/allinone/textlab/v0:knight        one word
/r/moul/x/allinone/textlab/v0:knight/night  compared with another
/r/moul/x/allinone/textlab/v0:1987          read as a roman numeral
```

Eight packages: `soundex`, `levenshtein`, `rot13`, `piglatin`, `romannum`,
plus `kit/ui`, `md`, `realmpath` and `r/moul/config`.

## What the combination shows

soundex and levenshtein both claim to tell you whether two words are alike, and
they are measuring different things. soundex keys on the **first letter** and
then on consonant classes, so it is blind to how the rest is spelled.
levenshtein counts edits and is blind to how it sounds.

| pair | soundex | levenshtein |
|---|---|---|
| `knight` / `night` | K523 vs N230, **unrelated** | 1 edit, 83% similar |
| `robert` / `rupert` | R163 vs R163, **identical** | 2 edits, 67% similar |

The first is the clean case: one edit apart, and yet soundex says no, because
the silent K changes the first character of the code. Measured 2026-09-23
against the packages in this tree and pinned by `TestTheDisagreement`, so the
page cannot start saying something false without the suite going red.

## One defect worth keeping in mind

`romannum.FromRoman` **panics** on a string that is not a roman numeral rather
than returning zero. The input here comes out of a URL, so it is screened by
`isRomanNumeral` first. Without that screen the default view aborted, because
`knight` is not a roman numeral and neither is most of what anyone would type.

No state at all: the input comes from the render path and nothing is stored.
