package calc

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # RPN Calculator
	//
	// ## Result
	//
	// _(empty stack)_
	//
	// ## Stack (bottom → top)
	//
	// _empty_
	//
	// ## Usage
	//
	// Reverse Polish Notation: operands first, operator last.
	//
	// - `Push("5")` then `Push("3")` then `Push("+")` → `8`
	// - Supported operators: `+`, `-`, `*`, `/` (integer division)
	// - An operator pops the top two values (a, b) and pushes `a op b`.
	// - `Clear()` empties the stack.
	// - Divide-by-zero and underflow abort the transaction.
}
