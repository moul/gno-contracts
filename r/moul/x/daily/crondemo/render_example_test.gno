package crondemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand
// typed: every instant in it is computed by the library under test, so a
// change in the parser shows up here as a diff rather than as prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Cron expressions
	//
	// The five-field crontab grammar, parsed and answered: given a schedule and an instant, when does it next fire. Demoing the [`p/moul/x/daily/cron`](/p/moul/x/daily/cron/v0) library.
	//
	// ## The grammar
	//
	// | position | field | range | names |
	// | --- | --- | --- | --- |
	// | 1 | minute | `0-59` |  |
	// | 2 | hour | `0-23` |  |
	// | 3 | day of month | `1-31` |  |
	// | 4 | month | `1-12` | `jan`..`dec` |
	// | 5 | day of week | `0-7` | `sun`..`sat` |
	//
	// Every field is a comma-separated list whose items are a value, a range, a star, or any of those with a step: `5`, `5-30`, `*`, `*/15`, `5-30/5`, `5/20`. In the weekday field `0` and `7` are both Sunday, which is what keeps `5-7` meaning Friday through Sunday instead of running backwards.
	//
	// ## Next firing times
	//
	// Measured from `2026-03-10 09:17 tue`, and strictly after it: a schedule handed its own firing time answers with the following one.
	//
	// | expression | meaning | next | then | and then |
	// | --- | --- | --- | --- | --- |
	// | `* * * * *` | every minute | 2026-03-10 09:18 tue | 2026-03-10 09:19 tue | 2026-03-10 09:20 tue |
	// | `*/15 * * * *` | every quarter hour | 2026-03-10 09:30 tue | 2026-03-10 09:45 tue | 2026-03-10 10:00 tue |
	// | `0 * * * *` | on the hour | 2026-03-10 10:00 tue | 2026-03-10 11:00 tue | 2026-03-10 12:00 tue |
	// | `5,25,45 * * * *` | a list of minutes | 2026-03-10 09:25 tue | 2026-03-10 09:45 tue | 2026-03-10 10:05 tue |
	// | `5/20 * * * *` | from minute 5, every 20 | 2026-03-10 09:25 tue | 2026-03-10 09:45 tue | 2026-03-10 10:05 tue |
	// | `30 8 * * 1-5` | weekday mornings | 2026-03-11 08:30 wed | 2026-03-12 08:30 thu | 2026-03-13 08:30 fri |
	// | `0 12 * * sat,sun` | weekend noon | 2026-03-14 12:00 sat | 2026-03-15 12:00 sun | 2026-03-21 12:00 sat |
	// | `0 0 1 jan,jul *` | twice a year | 2026-07-01 00:00 wed | 2027-01-01 00:00 fri | 2027-07-01 00:00 thu |
	// | `0 0 29 2 *` | the leap day | 2028-02-29 00:00 tue | 2032-02-29 00:00 sun | 2036-02-29 00:00 fri |
	//
	// The last row is not a failure. `0 0 29 2 *` is a perfectly well formed expression that skips three years out of four, and the parser has no business rejecting it.
	//
	// ## The two day fields are a union
	//
	// This is the rule a reimplementation gets wrong. When **both** the day-of-month and the day-of-week field are narrowed, a day matches when **either** does. `0 0 13 * 5` is the classic: the 13th of the month OR any Friday, never the intersection, which is why it also fires on ordinary Fridays.
	//
	// | expression | day of month | day of week | combined | next three |
	// | --- | --- | --- | --- | --- |
	// | `0 0 13 * 5` | the 13th | Friday | **either** | 2026-03-13 00:00 fri, 2026-03-20 00:00 fri, 2026-03-27 00:00 fri |
	// | `0 0 13 * *` | the 13th | any | the 13th | 2026-03-13 00:00 fri, 2026-04-13 00:00 mon, 2026-05-13 00:00 wed |
	// | `0 0 * * 5` | any | Friday | Friday | 2026-03-13 00:00 fri, 2026-03-20 00:00 fri, 2026-03-27 00:00 fri |
	//
	// When only one of the two is narrowed the other matches every day, so the union and the intersection agree and there is nothing to decide. The rule only bites on the first row.
	//
	// ## Macros
	//
	// | macro | expands to | next |
	// | --- | --- | --- |
	// | `@hourly` | `0 * * * *` | 2026-03-10 10:00 tue |
	// | `@daily` | `0 0 * * *` | 2026-03-11 00:00 wed |
	// | `@weekly` | `0 0 * * 0` | 2026-03-15 00:00 sun |
	// | `@monthly` | `0 0 1 * *` | 2026-04-01 00:00 wed |
	// | `@yearly` | `0 0 1 1 *` | 2027-01-01 00:00 fri |
	//
	// `@annually` is `@yearly` and `@midnight` is `@daily`. A schedule reports the expression it was parsed from, so a macro stays a macro on the way back out.
	//
	// ## What a bad expression says
	//
	// | expression | error |
	// | --- | --- |
	// | `* * * *` | cron: want 5 fields, got 4 in "\* \* \* \*" |
	// | `60 * * * *` | cron: minute field "60": out of range 0\-59: 60 |
	// | `* * * * 8` | cron: day of week field "8": out of range 0\-7: 8 |
	// | `* * * * 5-1` | cron: day of week field "5\-1": range runs backwards: "5\-1" |
	// | `*/0 * * * *` | cron: minute field "\*/0": step must be at least 1, got 0 |
	// | `@fortnightly` | cron: unknown macro "@fortnightly" |
	//
	// The field is named in the message. Five fields all accept numbers, so `out of range` on its own says nothing about which one to go and fix.
	//
	// ## Why a realm would want this
	//
	// A chain has no timer. Nothing on gno.land wakes a realm up, so a schedule is not a thing that runs: it is a thing that is *checked*. A realm stores the expression, and whoever calls in next asks whether the due instant has passed. `Next` turns a crontab line into that one comparison, and `Matches` answers it for the current block without any arithmetic at the call site.
	//
	// Everything here is UTC on purpose. A block timestamp carries no local zone, and a schedule whose answer depended on one would not be the same schedule on every validating node.
}
