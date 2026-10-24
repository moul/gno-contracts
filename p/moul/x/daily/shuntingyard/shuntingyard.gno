// Package shuntingyard turns an infix arithmetic expression into reverse
// Polish notation and evaluates it over int64, with Dijkstra's shunting-yard
// algorithm (1961).
//
// A realm that wants to take a formula from a caller has two bad options and
// this one. Hard-coding the arithmetic means a new package path for every new
// formula, and a public path can never be redeployed. Accepting a pre-built
// RPN string pushes the parsing onto whoever is sending the transaction, who
// then has to be trusted to have parsed it the same way. Parsing infix on
// chain keeps the formula a piece of data and the meaning a piece of code.
//
// Three properties make it usable for that rather than only interesting:
//
//   - Every arithmetic result is checked. An expression that would wrap int64
//     returns [ErrOverflow] instead of a plausible wrong number, which matters
//     because the usual reason to evaluate a caller's formula is to compute an
//     amount.
//   - Nothing panics. Every refusal is an error value, so a Render that
//     evaluates a stored expression cannot be made permanently unreadable by
//     one bad input.
//   - Parsing and evaluation are separate. [ToRPN] answers whether an
//     expression is well formed, and the RPN it returns is a bounded program a
//     realm can store and re-run without parsing it again.
//
// Integers only, deliberately: see the package README.
//
// A live demo of this package is at
// [r/moul/x/daily/shuntingyarddemo](/r/moul/x/daily/shuntingyarddemo/v0).
package shuntingyard

import (
	"errors"
	"math"
	"strconv"
	"strings"
)

// MaxTokens bounds how long an expression may be, so a caller cannot size the
// two stacks from unbounded input and make the allocation itself the attack.
// It is a token count, not a byte count: whitespace and long literals are free.
const MaxTokens = 1024

// Operator spellings, as they appear in a [Token]. The two unary forms are
// separate operators rather than a flag, because a prefix minus and a binary
// minus have different arities and different precedence, and conflating them
// is the classic way a shunting-yard implementation evaluates -3^2 as 9.
const (
	OpAdd = "+"
	OpSub = "-"
	OpMul = "*"
	OpDiv = "/"
	OpMod = "%"
	OpPow = "^"
	OpNeg = "u-"
	OpPos = "u+"
)

// Evaluation failures. Each one is a value rather than a panic: see the
// package doc.
var (
	ErrDivByZero    = errors.New("shuntingyard: division by zero")
	ErrOverflow     = errors.New("shuntingyard: int64 overflow")
	ErrNegExponent  = errors.New("shuntingyard: negative exponent")
	ErrTooLong      = errors.New("shuntingyard: too many tokens")
	ErrMalformedRPN = errors.New("shuntingyard: malformed RPN")
)

// SyntaxError is returned by [Tokenize] and [ToRPN]. Pos is the byte offset in
// the source where the problem was noticed, so a caller can point at it.
type SyntaxError struct {
	Pos int
	Msg string
}

// Error implements the error interface.
func (e *SyntaxError) Error() string {
	return "shuntingyard: " + e.Msg + " at offset " + strconv.Itoa(e.Pos)
}

// Kind tells a [Token] apart.
type Kind uint8

// The four token kinds.
const (
	KindNumber Kind = iota
	KindOperator
	KindLParen
	KindRParen
)

// Token is one lexical unit of an expression. Num is meaningful only for
// [KindNumber] and Op only for [KindOperator]. Pos is the byte offset the
// token started at, kept so an error can name a place rather than a symbol.
type Token struct {
	Kind Kind
	Num  int64
	Op   string
	Pos  int
}

// String renders a token the way it is written in an expression, which is also
// how [FormatRPN] prints it.
func (t Token) String() string {
	switch t.Kind {
	case KindNumber:
		return strconv.FormatInt(t.Num, 10)
	case KindOperator:
		return t.Op
	case KindLParen:
		return "("
	case KindRParen:
		return ")"
	}
	return "?"
}

// OpInfo describes one operator: its precedence, whether it associates to the
// right, and whether it is the prefix unary form.
type OpInfo struct {
	Op    string
	Prec  int
	Right bool
	Unary bool
}

// operators is the whole precedence table. Everything about how an expression
// groups is in these eight rows, which is the point of the algorithm: the
// grouping is data, not control flow, so adding an operator is a row.
//
// The unary forms sit between the multiplicative operators and the power on
// purpose. Below the power is what makes -3^2 read as -(3^2), which is how
// every language that has both spells it; above multiplication is what makes
// -2*3 read as (-2)*3 rather than -(2*3). The two happen to agree here, but
// they would not for an operator that is not distributive.
var operators = []OpInfo{
	{Op: OpAdd, Prec: 1},
	{Op: OpSub, Prec: 1},
	{Op: OpMul, Prec: 2},
	{Op: OpDiv, Prec: 2},
	{Op: OpMod, Prec: 2},
	{Op: OpNeg, Prec: 3, Right: true, Unary: true},
	{Op: OpPos, Prec: 3, Right: true, Unary: true},
	{Op: OpPow, Prec: 4, Right: true},
}

// Operators returns the precedence table, lowest precedence first. The slice
// is a copy: a caller rendering it must not be able to reorder the parser.
func Operators() []OpInfo {
	out := make([]OpInfo, len(operators))
	copy(out, operators)
	return out
}

// lookup returns the table row for an operator spelling.
func lookup(op string) (OpInfo, bool) {
	for _, info := range operators {
		if info.Op == op {
			return info, true
		}
	}
	return OpInfo{}, false
}

// Tokenize splits an infix expression into tokens, resolving a leading '+' or
// '-' to its unary form ([OpPos], [OpNeg]) from what came before it.
//
// It validates characters and literals only. Whether the tokens form an
// expression is [ToRPN]'s question, because that is the pass that knows what
// may follow what.
func Tokenize(src string) ([]Token, error) {
	var out []Token
	for i := 0; i < len(src); {
		c := src[i]

		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			i++
			continue
		}

		switch {
		case c >= '0' && c <= '9':
			j := i
			for j < len(src) && src[j] >= '0' && src[j] <= '9' {
				j++
			}
			n, err := strconv.ParseInt(src[i:j], 10, 64)
			if err != nil {
				return nil, &SyntaxError{Pos: i, Msg: "integer literal out of range"}
			}
			out = append(out, Token{Kind: KindNumber, Num: n, Pos: i})
			i = j
		case c == '(':
			out = append(out, Token{Kind: KindLParen, Pos: i})
			i++
		case c == ')':
			out = append(out, Token{Kind: KindRParen, Pos: i})
			i++
		default:
			op := binaryOp(c)
			if op == "" {
				return nil, &SyntaxError{Pos: i, Msg: "unexpected character " + quote(src[i:i+1])}
			}
			if prefixPosition(out) {
				switch op {
				case OpAdd:
					op = OpPos
				case OpSub:
					op = OpNeg
				}
			}
			out = append(out, Token{Kind: KindOperator, Op: op, Pos: i})
			i++
		}

		if len(out) > MaxTokens {
			return nil, ErrTooLong
		}
	}
	return out, nil
}

// binaryOp maps a byte to the operator it spells, or "" if it spells none.
func binaryOp(c byte) string {
	switch c {
	case '+':
		return OpAdd
	case '-':
		return OpSub
	case '*':
		return OpMul
	case '/':
		return OpDiv
	case '%':
		return OpMod
	case '^':
		return OpPow
	}
	return ""
}

// prefixPosition reports whether the next operator would be a prefix one:
// nothing before it, or an operator or an opening parenthesis before it. A
// closing parenthesis and a number both end an operand, so what follows them
// is binary.
func prefixPosition(out []Token) bool {
	if len(out) == 0 {
		return true
	}
	prev := out[len(out)-1]
	return prev.Kind == KindOperator || prev.Kind == KindLParen
}

// ToRPN converts an infix token stream to reverse Polish notation, rejecting
// anything that is not a well-formed expression.
//
// The validity check is one bit of state: whether an operand or an operator is
// expected next. That single bit is what rejects "1 2", "1+" and "()", and it
// costs nothing on top of the conversion the function is doing anyway.
func ToRPN(in []Token) ([]Token, error) {
	if len(in) > MaxTokens {
		return nil, ErrTooLong
	}

	var out, stack []Token
	expectOperand := true
	end := 0

	for _, tok := range in {
		end = tok.Pos + 1

		switch tok.Kind {
		case KindNumber:
			if !expectOperand {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unexpected number"}
			}
			out = append(out, tok)
			expectOperand = false

		case KindLParen:
			if !expectOperand {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unexpected " + quote("(")}
			}
			stack = append(stack, tok)

		case KindRParen:
			if expectOperand {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unexpected " + quote(")")}
			}
			for len(stack) > 0 && stack[len(stack)-1].Kind != KindLParen {
				out = append(out, stack[len(stack)-1])
				stack = stack[:len(stack)-1]
			}
			if len(stack) == 0 {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unbalanced " + quote(")")}
			}
			stack = stack[:len(stack)-1]
			expectOperand = false

		case KindOperator:
			info, ok := lookup(tok.Op)
			if !ok {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unknown operator " + quote(tok.Op)}
			}
			// A unary operator is only ever an operand's prefix, a binary one
			// only ever an operand's successor. One comparison covers both.
			if info.Unary != expectOperand {
				return nil, &SyntaxError{Pos: tok.Pos, Msg: "unexpected operator " + quote(tok.Op)}
			}
			// A prefix operator pops nothing: whatever is on the stack is
			// waiting for a right operand that this operator is about to
			// build, so popping it here would apply it to nothing.
			if !info.Unary {
				for len(stack) > 0 {
					top := stack[len(stack)-1]
					if top.Kind != KindOperator {
						break
					}
					ti, _ := lookup(top.Op)
					if ti.Prec > info.Prec || (ti.Prec == info.Prec && !info.Right) {
						out = append(out, top)
						stack = stack[:len(stack)-1]
						continue
					}
					break
				}
			}
			stack = append(stack, tok)
			expectOperand = true

		default:
			return nil, &SyntaxError{Pos: tok.Pos, Msg: "unknown token"}
		}
	}

	if expectOperand {
		return nil, &SyntaxError{Pos: end, Msg: "unexpected end of expression"}
	}

	for len(stack) > 0 {
		top := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if top.Kind == KindLParen {
			return nil, &SyntaxError{Pos: top.Pos, Msg: "unbalanced " + quote("(")}
		}
		out = append(out, top)
	}
	return out, nil
}

// EvalRPN evaluates a reverse Polish token stream over int64.
//
// It re-checks everything [ToRPN] guarantees, because the RPN is the part a
// realm would store and re-run, and a stored program is an input like any
// other by the time it is read back.
func EvalRPN(rpn []Token) (int64, error) {
	if len(rpn) > MaxTokens {
		return 0, ErrTooLong
	}

	var stack []int64
	for _, tok := range rpn {
		if tok.Kind == KindNumber {
			stack = append(stack, tok.Num)
			continue
		}
		if tok.Kind != KindOperator {
			return 0, ErrMalformedRPN
		}

		info, ok := lookup(tok.Op)
		if !ok {
			return 0, ErrMalformedRPN
		}

		if info.Unary {
			if len(stack) < 1 {
				return 0, ErrMalformedRPN
			}
			v, err := applyUnary(tok.Op, stack[len(stack)-1])
			if err != nil {
				return 0, err
			}
			stack[len(stack)-1] = v
			continue
		}

		if len(stack) < 2 {
			return 0, ErrMalformedRPN
		}
		a, b := stack[len(stack)-2], stack[len(stack)-1]
		stack = stack[:len(stack)-2]
		v, err := applyBinary(tok.Op, a, b)
		if err != nil {
			return 0, err
		}
		stack = append(stack, v)
	}

	if len(stack) != 1 {
		return 0, ErrMalformedRPN
	}
	return stack[0], nil
}

// Eval tokenizes, converts and evaluates an infix expression in one call.
func Eval(src string) (int64, error) {
	toks, err := Tokenize(src)
	if err != nil {
		return 0, err
	}
	rpn, err := ToRPN(toks)
	if err != nil {
		return 0, err
	}
	return EvalRPN(rpn)
}

// FormatRPN renders a token stream space-separated, the usual way RPN is
// written down.
func FormatRPN(toks []Token) string {
	var b strings.Builder
	for i, t := range toks {
		if i > 0 {
			b.WriteString(" ")
		}
		b.WriteString(t.String())
	}
	return b.String()
}

// applyUnary applies a prefix operator.
func applyUnary(op string, a int64) (int64, error) {
	switch op {
	case OpNeg:
		// The one asymmetry of two's complement: there is no positive
		// counterpart to the smallest int64, so negating it wraps to itself.
		if a == math.MinInt64 {
			return 0, ErrOverflow
		}
		return -a, nil
	case OpPos:
		return a, nil
	}
	return 0, ErrMalformedRPN
}

// applyBinary applies an infix operator, refusing anything it cannot compute
// exactly.
func applyBinary(op string, a, b int64) (int64, error) {
	switch op {
	case OpAdd:
		if (b > 0 && a > math.MaxInt64-b) || (b < 0 && a < math.MinInt64-b) {
			return 0, ErrOverflow
		}
		return a + b, nil
	case OpSub:
		if (b < 0 && a > math.MaxInt64+b) || (b > 0 && a < math.MinInt64+b) {
			return 0, ErrOverflow
		}
		return a - b, nil
	case OpMul:
		return mulChecked(a, b)
	case OpDiv:
		if b == 0 {
			return 0, ErrDivByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case OpMod:
		if b == 0 {
			return 0, ErrDivByZero
		}
		// MinInt64 % -1 is 0 mathematically, but the hardware instruction
		// behind it is the same one that overflows on the division.
		if a == math.MinInt64 && b == -1 {
			return 0, nil
		}
		return a % b, nil
	case OpPow:
		return powChecked(a, b)
	}
	return 0, ErrMalformedRPN
}

// mulChecked multiplies, reporting [ErrOverflow] rather than wrapping.
func mulChecked(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
		return 0, ErrOverflow
	}
	p := a * b
	// The division is the check: it recovers a exactly unless the product
	// wrapped. Comparing against a precomputed limit instead needs a different
	// limit per sign combination, and that is where these get written wrong.
	if p/b != a {
		return 0, ErrOverflow
	}
	return p, nil
}

// powChecked raises base to exp by squaring, in O(log exp) checked
// multiplications.
func powChecked(base, exp int64) (int64, error) {
	if exp < 0 {
		return 0, ErrNegExponent
	}

	result := int64(1)
	b, e := base, exp
	for e > 0 {
		if e&1 == 1 {
			v, err := mulChecked(result, b)
			if err != nil {
				return 0, err
			}
			result = v
		}
		e >>= 1
		// Squaring the base one last time after the final bit is consumed
		// would overflow on exponents that are perfectly representable, so
		// the loop stops before the squaring it does not need.
		if e == 0 {
			break
		}
		v, err := mulChecked(b, b)
		if err != nil {
			return 0, err
		}
		b = v
	}
	return result, nil
}

// quote wraps a spelling in double quotes for an error message.
func quote(s string) string {
	return "\"" + s + "\""
}
