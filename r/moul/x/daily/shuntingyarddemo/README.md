# `gno.land/r/moul/x/daily/shuntingyarddemo/v0`

**A gnoweb demo of [`p/moul/x/daily/shuntingyard`](/p/moul/x/daily/shuntingyard/v0)**: the three
stages of the algorithm, and the refusals that make it safe to point at a caller's string.

Two pages, both pure functions of their input:

| path | shows |
|---|---|
| `Render("")` | worked examples, the precedence table, and what the parser refuses |
| `Render("?e=2*(3%2B4)")` | the tokens, the reverse Polish notation and the value of one expression |

The root page is built from fixed tables in the source, never from chain state,
which is what lets an example test pin it byte for byte. The `?e=` page is built
from the query alone, so it is equally pinnable despite taking caller input.

**The demo contains no parsing and no arithmetic of its own.** Every RPN string
and every number on the page is computed by the library at render time, so a
change in the parser shows up in the pinned output as a diff rather than being
described in prose that can quietly go stale.

**A `+` in the query string decodes to a space**, which is why the try-it links
percent-encode it. Whitespace is insignificant to the parser, so an unescaped
`?e=2+3` would arrive as `2 3` and be rejected as two numbers in a row: a
puzzling error about an expression the caller never typed.

The expression and every error message are escaped with `ui.Inline` before they
reach the page. Tokens and the RPN are not, and are shown as code spans instead:
`Tokenize` accepts a closed alphabet (digits, parentheses and the six operator
bytes) and rejects everything else, so a token can only ever spell itself, and
running one through an escaper would put a literal backslash inside a code span
where markdown does not process escapes.

The realm is stateless and has no transactions. Nothing it renders depends on
the block height, the caller or the clock.
