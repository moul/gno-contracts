# `gno.land/r/moul/x/daily/crondemo/v0`

A gnoweb demo of [`p/moul/x/daily/cron`](/p/moul/x/daily/cron/v0): the five-field
crontab grammar, the next firing times of nine schedules, the union rule that
governs the two day fields, the `@macros`, and what a bad expression says.

The realm holds no scheduling logic and no state. Every instant on the page is
computed from one fixed anchor, a Tuesday morning in March 2026, rather than from
`time.Now()`: a block timestamp would make the page different on every call and
identical to nothing, and an example test could not pin it.

The section worth reading is **the two day fields are a union**. `0 0 13 * 5` is
the 13th of the month or any Friday, and the table shows it firing on three
consecutive Fridays to prove the point. The row below it narrows only one field,
where the union and the intersection agree and the rule cannot be observed, which
is exactly why the bug survives in so many reimplementations.

The leap-day row is the other one to look at: `0 0 29 2 *` skips three years out
of four, and the parser has no business rejecting it.

```
Render("")  -> the full demo
```
