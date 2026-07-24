package calc

import (
	"chain"
	"errors"
	"strconv"
	"strings"
)

// stack holds the shared RPN operand stack, bottom (index 0) to top.
var stack []int

// ErrUnderflow is raised when an operator needs more operands than available.
var ErrUnderflow = errors.New("stack underflow: operator needs two operands")

// ErrDivByZero is raised on division by zero.
var ErrDivByZero = errors.New("division by zero")

// Push consumes a single token: an integer is pushed onto the stack; an
// operator (+, -, *, /) pops two operands and pushes the result.
func Push(cur realm, token string) {
	token = strings.TrimSpace(token)
	if token == "" {
		panic("empty token")
	}

	switch token {
	case "+", "-", "*", "/":
		if len(stack) < 2 {
			panic(ErrUnderflow.Error())
		}
		b := stack[len(stack)-1]
		a := stack[len(stack)-2]
		stack = stack[:len(stack)-2]

		var r int
		switch token {
		case "+":
			r = a + b
		case "-":
			r = a - b
		case "*":
			r = a * b
		case "/":
			if b == 0 {
				panic(ErrDivByZero.Error())
			}
			r = a / b
		}
		stack = append(stack, r)
		chain.Emit("Op", "op", token, "result", strconv.Itoa(r))
	default:
		n, err := strconv.Atoi(token)
		if err != nil {
			panic("invalid token: expected integer or one of + - * /, got " + token)
		}
		stack = append(stack, n)
		chain.Emit("Push", "value", strconv.Itoa(n))
	}
}

// Clear empties the shared stack.
func Clear(cur realm) {
	stack = nil
	chain.Emit("Clear")
}

// Depth returns the number of values currently on the stack.
func Depth() int {
	return len(stack)
}

// Top returns the top value and whether the stack is non-empty.
func Top() (int, bool) {
	if len(stack) == 0 {
		return 0, false
	}
	return stack[len(stack)-1], true
}

// Render renders the current stack, the top value as the result, and a
// short usage guide.
func Render(path string) string {
	var sb strings.Builder
	sb.WriteString("# RPN Calculator\n\n")

	sb.WriteString("## Result\n\n")
	if top, ok := Top(); ok {
		sb.WriteString("**")
		sb.WriteString(strconv.Itoa(top))
		sb.WriteString("**\n\n")
	} else {
		sb.WriteString("_(empty stack)_\n\n")
	}

	sb.WriteString("## Stack (bottom → top)\n\n")
	if len(stack) == 0 {
		sb.WriteString("_empty_\n\n")
	} else {
		for i, v := range stack {
			sb.WriteString(strconv.Itoa(i))
			sb.WriteString(". ")
			sb.WriteString(strconv.Itoa(v))
			sb.WriteString("\n")
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Usage\n\n")
	sb.WriteString("Reverse Polish Notation: operands first, operator last.\n\n")
	sb.WriteString("- `Push(\"5\")` then `Push(\"3\")` then `Push(\"+\")` → `8`\n")
	sb.WriteString("- Supported operators: `+`, `-`, `*`, `/` (integer division)\n")
	sb.WriteString("- An operator pops the top two values (a, b) and pushes `a op b`.\n")
	sb.WriteString("- `Clear()` empties the stack.\n")
	sb.WriteString("- Divide-by-zero and underflow abort the transaction.\n")

	return sb.String()
}
