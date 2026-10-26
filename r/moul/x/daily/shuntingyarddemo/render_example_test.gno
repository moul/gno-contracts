package shuntingyarddemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand typed:
// every RPN string and every value in it is computed by the library under
// test, so a change in the parser shows up here as a diff rather than as
// prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Shunting-yard
	//
	// Dijkstra's 1961 algorithm, demoing the [`p/moul/x/daily/shuntingyard`](/p/moul/x/daily/shuntingyard/v0) library: an infix expression becomes reverse Polish notation in one left-to-right pass, with one stack and no recursion, and the RPN evaluates with one more stack.
	//
	// ## Worked examples
	//
	// | expression | RPN | value | why it is here |
	// | --- | --- | --- | --- |
	// | `2+3*4` | `2 3 4 * +` | `14` | multiplication binds tighter |
	// | `(2+3)*4` | `2 3 + 4 *` | `20` | parentheses beat precedence |
	// | `10-3-2` | `10 3 - 2 -` | `5` | subtraction associates left |
	// | `2^3^2` | `2 3 2 ^ ^` | `512` | but power associates right |
	// | `-3^2` | `3 2 ^ u-` | `-9` | a prefix minus binds looser than a power |
	// | `3*-2` | `3 2 u- *` | `-6` | the same byte, now unary, after an operator |
	// | `-7/2` | `7 u- 2 /` | `-3` | integer division truncates toward zero |
	// | `-7%2` | `7 u- 2 %` | `-1` | and the remainder keeps the dividend's sign |
	//
	// Every cell above is computed by the library at render time. The RPN column is the whole output of the conversion: an expression that groups surprisingly groups visibly.
	//
	// ## The precedence table is the parser
	//
	// Grouping is data here, not control flow. These eight rows are the only thing that decides how an expression reads, which is why adding an operator is a row rather than a branch.
	//
	// | operator | precedence | associativity | arity |
	// | --- | --- | --- | --- |
	// | `+` | 1 | left | binary |
	// | `-` | 1 | left | binary |
	// | `*` | 2 | left | binary |
	// | `/` | 2 | left | binary |
	// | `%` | 2 | left | binary |
	// | `u-` | 3 | right | unary prefix |
	// | `u+` | 3 | right | unary prefix |
	// | `^` | 4 | right | binary |
	//
	// `u-` and `u+` are the prefix forms. They are separate operators rather than a flag on `-` and `+` because they take one operand instead of two and sit at a different precedence, and conflating the two is how a parser ends up reading `-3^2` as `9`.
	//
	// ## What it refuses
	//
	// None of these panics. A realm that evaluates a stored expression inside `Render` cannot be made permanently unreadable by one bad input, and an expression that would wrap `int64` says so instead of returning a plausible wrong amount.
	//
	// | expression | error |
	// | --- | --- |
	// | `1/0` | shuntingyard: division by zero |
	// | `2^-1` | shuntingyard: negative exponent |
	// | `9223372036854775807+1` | shuntingyard: int64 overflow |
	// | `2^64` | shuntingyard: int64 overflow |
	// | `1 2` | shuntingyard: unexpected number at offset 2 |
	// | `(1` | shuntingyard: unbalanced "\(" at offset 0 |
	// | `1$2` | shuntingyard: unexpected character "$" at offset 1 |
	//
	// ## Try one
	//
	// [`2+3*4`](/r/moul/x/daily/shuntingyarddemo/v0:?e=2%2B3%2A4) · [`(2+3)*4`](/r/moul/x/daily/shuntingyarddemo/v0:?e=%282%2B3%29%2A4) · [`10-3-2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=10-3-2) · [`2^3^2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=2%5E3%5E2) · [`-3^2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=-3%5E2) · [`3*-2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=3%2A-2) · [`-7/2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=-7%2F2) · [`-7%2`](/r/moul/x/daily/shuntingyarddemo/v0:?e=-7%252)
	//
	// Or append your own: `?e=2*(3+4)`.
}

// ExampleRender_expression pins the per-expression page, which is the one a
// caller reaches with their own string in it.
func ExampleRender_expression() {
	print(Render("?e=2*(3%2B4)"))
	// Output:
	// # Shunting-yard: 2\*\(3\+4\)
	//
	// [back to the demo](/r/moul/x/daily/shuntingyarddemo/v0:)
	//
	// ## Tokens
	//
	// | # | kind | token | offset |
	// | --- | --- | --- | --- |
	// | 0 | number | `2` | 0 |
	// | 1 | operator | `*` | 1 |
	// | 2 | ( | `(` | 2 |
	// | 3 | number | `3` | 3 |
	// | 4 | operator | `+` | 4 |
	// | 5 | number | `4` | 5 |
	// | 6 | ) | `)` | 6 |
	//
	// ## Reverse Polish notation
	//
	// `2 3 4 + *`
	//
	// ## Value
	//
	// `14`
}

// ExampleRender_rejected pins a refusal, so the page that answers bad input
// is covered as well as the page that answers good input.
func ExampleRender_rejected() {
	print(Render("?e=1/0"))
	// Output:
	// # Shunting-yard: 1/0
	//
	// [back to the demo](/r/moul/x/daily/shuntingyarddemo/v0:)
	//
	// ## Tokens
	//
	// | # | kind | token | offset |
	// | --- | --- | --- | --- |
	// | 0 | number | `1` | 0 |
	// | 1 | operator | `/` | 1 |
	// | 2 | number | `0` | 2 |
	//
	// ## Reverse Polish notation
	//
	// `1 0 /`
	//
	// ## Rejected while evaluating it
	//
	// shuntingyard: division by zero
}
