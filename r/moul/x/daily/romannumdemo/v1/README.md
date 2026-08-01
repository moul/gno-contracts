# `gno.land/r/moul/x/daily/romannumdemo/v1`

Interactive gnoweb **demo of the [`p/moul/x/daily/romannum`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/romannum/v1)
Roman-numeral library** — it renders a table of worked examples and interactive
integer→Roman and Roman→integer conversions. It has no conversion logic of its own.

## Render paths

- `:` / root — a table of example conversions (1, 4, 9, 40, 90, 400, 900, 2024, 3999, …).
- `:/<n>` — integer → Roman, e.g. [`:/2024`](https://gno.land/r/moul/x/daily/romannumdemo/v1:2024) → `MMXXIV`.
- `:/r/<roman>` — Roman → integer, e.g. [`:/r/MMXXIV`](https://gno.land/r/moul/x/daily/romannumdemo/v1:r/MMXXIV) → `2024` (case-insensitive).
