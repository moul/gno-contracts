# RPN Calculator

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A shared, stack-based Reverse Polish Notation calculator realm. Anyone can push
tokens onto a single shared stack: integers are pushed as-is, while an operator
(`+`, `-`, `*`, `/`) pops the top two operands and pushes the result. Divide-by-zero
and stack underflow abort the transaction, and `Clear` resets the stack. `Render`
shows the current stack (bottom→top), the top value as the result, and a usage guide.

## Realm path

`gno.land/r/REPLACE_ADDR/calc`

## Example calls

```
# Compute (5 3 +) = 8
Push("5")
Push("3")
Push("+")

# Chain: (10 4 -) 2 * = 12
Push("10")
Push("4")
Push("-")
Push("2")
Push("*")

# Reset
Clear()
```

Read the current state via `Render` (e.g. the realm's rendered page).
