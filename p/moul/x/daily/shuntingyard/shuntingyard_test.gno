package shuntingyard

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestEval pins the grouping rules. Every want below was computed by hand:
// a parser checked against another parser only proves the two agree.
func TestEval(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want int64
	}{
		{"a single number", "42", 42},
		{"multiplication binds tighter", "2+3*4", 14},
		{"parentheses beat precedence", "(2+3)*4", 20},
		{"subtraction is left associative", "10-3-2", 5},
		{"division is left associative", "100/5/2", 10},
		{"power is right associative", "2^3^2", 512},
		{"unary minus binds looser than power", "-3^2", -9},
		{"unary minus over a group", "-(3+4)", -7},
		{"two unary minuses cancel", "--5", 5},
		{"unary after a binary operator", "3*-2", -6},
		{"unary plus is a no-op", "+7-+2", 5},
		{"a plus directly after a plus is unary", "1++2", 3},
		{"modulo", "17%5", 2},
		{"division truncates toward zero", "-7/2", -3},
		{"modulo takes the sign of the dividend", "-7%2", -1},
		{"whitespace is insignificant", "  1 +\t2 ", 3},
		{"zero to the zero is one", "0^0", 1},
		{"redundant nesting", "((((1+2))))*3", 9},
		{"a long chain", "1+2*3-4/2+5%3", 7},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Eval(tc.src)
			if err != nil {
				t.Errorf("Eval(%q) returned error %v", tc.src, err)
				return
			}
			if got != tc.want {
				t.Errorf("Eval(%q) = %d, want %d", tc.src, got, tc.want)
			}
		})
	}
}

// TestToRPN pins the conversion itself rather than the number that falls out
// of it. Eval would pass on a shape that happened to evaluate the same way.
func TestToRPN(t *testing.T) {
	cases := []struct {
		src  string
		want string
	}{
		{"2+3*4", "2 3 4 * +"},
		{"(2+3)*4", "2 3 + 4 *"},
		{"2^3^2", "2 3 2 ^ ^"},
		{"-3^2", "3 2 ^ u-"},
		{"3*-2", "3 2 u- *"},
		{"10-3-2", "10 3 - 2 -"},
		{"-(3+4)", "3 4 + u-"},
		{"1+2*3-4/2", "1 2 3 * + 4 2 / -"},
	}

	for _, tc := range cases {
		t.Run(tc.src, func(t *testing.T) {
			toks, err := Tokenize(tc.src)
			if err != nil {
				t.Errorf("Tokenize(%q) returned error %v", tc.src, err)
				return
			}
			rpn, err := ToRPN(toks)
			if err != nil {
				t.Errorf("ToRPN(%q) returned error %v", tc.src, err)
				return
			}
			if got := FormatRPN(rpn); got != tc.want {
				t.Errorf("ToRPN(%q) = %q, want %q", tc.src, got, tc.want)
			}
		})
	}
}

// TestTokenizeResolvesUnary is the one decision Tokenize makes on its own, and
// it is the decision a hand-rolled parser gets wrong: the same byte is two
// different operators depending on what precedes it.
func TestTokenizeResolvesUnary(t *testing.T) {
	cases := []struct {
		src    string
		at     int // index of the token under test
		wantOp string
	}{
		{"1-2", 1, OpSub},
		{"-1", 0, OpNeg},
		{"(-1)", 1, OpNeg},
		{"2*-1", 2, OpNeg},
		{"2^-1", 2, OpNeg},
		{"+1", 0, OpPos},
		{"1+2", 1, OpAdd},
	}

	for _, tc := range cases {
		t.Run(tc.src, func(t *testing.T) {
			toks, err := Tokenize(tc.src)
			if err != nil {
				t.Errorf("Tokenize(%q) returned error %v", tc.src, err)
				return
			}
			if tc.at >= len(toks) {
				t.Errorf("Tokenize(%q) produced %d tokens, want more than %d", tc.src, len(toks), tc.at)
				return
			}
			tok := toks[tc.at]
			if tok.Kind != KindOperator || tok.Op != tc.wantOp {
				t.Errorf("Tokenize(%q)[%d] = %v, want operator %q", tc.src, tc.at, tok, tc.wantOp)
			}
		})
	}
}

// TestTokenPositions pins the offsets, which are the only thing making a
// syntax error actionable to whoever typed the expression.
func TestTokenPositions(t *testing.T) {
	toks, err := Tokenize(" 12 + (3)")
	uassert.NoError(t, err)
	if len(toks) != 5 {
		t.Errorf("got %d tokens, want 5", len(toks))
		return
	}
	wantPos := []int{1, 4, 6, 7, 8}
	for i, want := range wantPos {
		if toks[i].Pos != want {
			t.Errorf("token %d (%v) at offset %d, want %d", i, toks[i], toks[i].Pos, want)
		}
	}
}

// TestSyntaxErrors covers every way an expression can be rejected before any
// arithmetic happens. The message is pinned whole, offset included.
func TestSyntaxErrors(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want string
	}{
		{"empty", "", "shuntingyard: unexpected end of expression at offset 0"},
		{"trailing operator", "1+", "shuntingyard: unexpected end of expression at offset 2"},
		{"two numbers", "1 2", "shuntingyard: unexpected number at offset 2"},
		{"leading binary operator", "*2", "shuntingyard: unexpected operator \"*\" at offset 0"},
		{"unclosed group", "(1", "shuntingyard: unbalanced \"(\" at offset 0"},
		{"unopened group", "1)", "shuntingyard: unbalanced \")\" at offset 1"},
		{"empty group", "()", "shuntingyard: unexpected \")\" at offset 1"},
		{"number before group", "2(3)", "shuntingyard: unexpected \"(\" at offset 1"},
		{"stray character", "1$2", "shuntingyard: unexpected character \"$\" at offset 1"},
		{"literal out of range", "99999999999999999999", "shuntingyard: integer literal out of range at offset 0"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Eval(tc.src)
			if err == nil {
				t.Errorf("Eval(%q) returned no error, want %q", tc.src, tc.want)
				return
			}
			if got := err.Error(); got != tc.want {
				t.Errorf("Eval(%q) error = %q, want %q", tc.src, got, tc.want)
			}
		})
	}
}

// TestEvalErrors is the half that makes the package usable for money: an
// expression that cannot be evaluated exactly says so instead of wrapping.
func TestEvalErrors(t *testing.T) {
	// minInt64 is only reachable through arithmetic: the literal itself is
	// out of range for the tokenizer, because a number token carries no sign.
	const mkMin = "((0-9223372036854775807)-1)"

	cases := []struct {
		name string
		src  string
		want error
	}{
		{"division by zero", "1/0", ErrDivByZero},
		{"modulo by zero", "1%0", ErrDivByZero},
		{"addition overflows", "9223372036854775807+1", ErrOverflow},
		{"multiplication overflows", "9223372036854775807*2", ErrOverflow},
		{"subtraction overflows", "(0-9223372036854775807)-2", ErrOverflow},
		{"power overflows", "2^64", ErrOverflow},
		{"negating the smallest int64 overflows", "-" + mkMin, ErrOverflow},
		{"dividing the smallest int64 by -1 overflows", mkMin + "/(0-1)", ErrOverflow},
		{"negative exponent", "2^-1", ErrNegExponent},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Eval(tc.src)
			if err != tc.want {
				t.Errorf("Eval(%q) = %d, %v, want error %v", tc.src, got, err, tc.want)
			}
		})
	}
}

// TestEvalNearTheLimit is the other side of TestEvalErrors: the checks must
// not reject an expression that fits exactly.
func TestEvalNearTheLimit(t *testing.T) {
	cases := []struct {
		src  string
		want int64
	}{
		{"9223372036854775806+1", 9223372036854775807},
		{"4611686018427387903*2", 9223372036854775806},
		{"2^62", 4611686018427387904},
		{"(0-9223372036854775807)-0", -9223372036854775807},
	}

	for _, tc := range cases {
		t.Run(tc.src, func(t *testing.T) {
			got, err := Eval(tc.src)
			if err != nil {
				t.Errorf("Eval(%q) returned error %v", tc.src, err)
				return
			}
			if got != tc.want {
				t.Errorf("Eval(%q) = %d, want %d", tc.src, got, tc.want)
			}
		})
	}
}

// TestEvalRPNRejectsMalformed matters because EvalRPN is exported: a realm may
// store the RPN and re-run it later, so it has to defend itself rather than
// trust that ToRPN produced what it is given.
func TestEvalRPNRejectsMalformed(t *testing.T) {
	cases := []struct {
		name string
		rpn  []Token
	}{
		{"empty", nil},
		{"operator with no operands", []Token{{Kind: KindOperator, Op: OpAdd}}},
		{"operator with one operand", []Token{{Kind: KindNumber, Num: 2}, {Kind: KindOperator, Op: OpAdd}}},
		{"two values left over", []Token{{Kind: KindNumber, Num: 2}, {Kind: KindNumber, Num: 3}}},
		{"unary with no operand", []Token{{Kind: KindOperator, Op: OpNeg}}},
		{"unknown operator", []Token{{Kind: KindNumber, Num: 2}, {Kind: KindNumber, Num: 3}, {Kind: KindOperator, Op: "&"}}},
		{"a parenthesis survived the conversion", []Token{{Kind: KindLParen}}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EvalRPN(tc.rpn)
			if err != ErrMalformedRPN {
				t.Errorf("EvalRPN(%v) = %d, %v, want %v", tc.rpn, got, err, ErrMalformedRPN)
			}
		})
	}
}

// TestTooLong pins the bound. Without it the two stacks are sized by whoever
// sends the transaction.
func TestTooLong(t *testing.T) {
	src := strings.Repeat("1+", MaxTokens) + "1"
	if _, err := Eval(src); err != ErrTooLong {
		t.Errorf("Eval of %d tokens returned %v, want %v", 2*MaxTokens+1, err, ErrTooLong)
	}

	// Just under the bound still parses, so the check is a bound and not an
	// off-by-one that rejects a long but legal expression.
	pairs := (MaxTokens - 1) / 2
	ok := strings.Repeat("1+", pairs) + "1"
	if _, err := Eval(ok); err != nil {
		t.Errorf("Eval of %d tokens returned %v, want it to parse", 2*pairs+1, err)
	}
}

// TestOperatorsIsACopy: the table is the parser's behaviour, so handing out
// the backing array would let a caller rendering it change how it parses.
func TestOperatorsIsACopy(t *testing.T) {
	got := Operators()
	if len(got) != len(operators) {
		t.Errorf("Operators() returned %d rows, want %d", len(got), len(operators))
		return
	}
	got[0].Prec = 99
	if operators[0].Prec == 99 {
		t.Errorf("Operators() handed out the table itself")
	}
}

// TestFormatRPNEmpty pins the only edge case the formatter has.
func TestFormatRPNEmpty(t *testing.T) {
	uassert.Equal(t, "", FormatRPN(nil))
}

// TestTokenString covers the four kinds, since FormatRPN and the demo both
// render through it.
func TestTokenString(t *testing.T) {
	uassert.Equal(t, "-7", Token{Kind: KindNumber, Num: -7}.String())
	uassert.Equal(t, "u-", Token{Kind: KindOperator, Op: OpNeg}.String())
	uassert.Equal(t, "(", Token{Kind: KindLParen}.String())
	uassert.Equal(t, ")", Token{Kind: KindRParen}.String())
}
