// Package shuntingyarddemo is a small gnoweb demo of the
// [p/moul/x/daily/shuntingyard](/p/moul/x/daily/shuntingyard/v0) library: it
// shows the three stages of the algorithm (tokens, reverse Polish notation,
// value) and the refusals that make it safe to point at a caller's string.
//
// It contains no parsing or arithmetic of its own, and it has no state. The
// root page is computed from the fixed tables at the top of this file, never
// from chain state, which is what lets an example test pin it; the `?e=`
// page is computed from the query alone, which is still a pure function of
// its input and therefore equally pinnable.
package shuntingyarddemo

import (
	"net/url"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/x/daily/shuntingyard/v0"
)

// selfPath is where this realm answers, used to build the try-it links.
const selfPath = "/r/moul/x/daily/shuntingyarddemo/v0:"

// worked are the expressions on the root page. Each one is here because it
// groups in a way the naive left-to-right reading gets wrong.
var worked = []struct {
	expr string
	why  string
}{
	{"2+3*4", "multiplication binds tighter"},
	{"(2+3)*4", "parentheses beat precedence"},
	{"10-3-2", "subtraction associates left"},
	{"2^3^2", "but power associates right"},
	{"-3^2", "a prefix minus binds looser than a power"},
	{"3*-2", "the same byte, now unary, after an operator"},
	{"-7/2", "integer division truncates toward zero"},
	{"-7%2", "and the remainder keeps the dividend's sign"},
}

// refused are the inputs worth showing precisely because nothing panics on
// them. A realm that renders a stored expression is one bad input away from a
// permanently broken page, and a public path cannot be redeployed.
var refused = []string{
	"1/0",
	"2^-1",
	"9223372036854775807+1",
	"2^64",
	"1 2",
	"(1",
	"1$2",
}

// Render renders the demo for gnoweb.
//
//	Render("")              -> the demo page
//	Render("?e=<expr>")     -> the three stages for one expression
func Render(path string) string {
	req := realmpath.Parse(path)
	// Any non-empty `e` goes to the per-expression page, including one that is
	// only whitespace: the parser already answers that with "unexpected end of
	// expression at offset 0", which is a better page than silently showing the
	// index to someone who asked a question.
	if expr := req.Query.Get("e"); expr != "" {
		return renderOne(expr)
	}
	return renderIndex()
}

// renderIndex is the fixed page: what the algorithm does, and what it refuses.
func renderIndex() string {
	var b strings.Builder

	b.WriteString("# Shunting-yard\n\n")
	b.WriteString("Dijkstra's 1961 algorithm, demoing the ")
	b.WriteString("[`p/moul/x/daily/shuntingyard`](/p/moul/x/daily/shuntingyard/v0) ")
	b.WriteString("library: an infix expression becomes reverse Polish notation ")
	b.WriteString("in one left-to-right pass, with one stack and no recursion, ")
	b.WriteString("and the RPN evaluates with one more stack.\n\n")

	b.WriteString("## Worked examples\n\n")
	wt := ui.NewTable("expression", "RPN", "value", "why it is here")
	for _, w := range worked {
		rpn, value := trace(w.expr)
		wt.Row("`"+w.expr+"`", "`"+rpn+"`", "`"+value+"`", w.why)
	}
	b.WriteString(wt.String() + "\n")
	b.WriteString("Every cell above is computed by the library at render time. ")
	b.WriteString("The RPN column is the whole output of the conversion: an ")
	b.WriteString("expression that groups surprisingly groups visibly.\n\n")

	b.WriteString("## The precedence table is the parser\n\n")
	b.WriteString("Grouping is data here, not control flow. These eight rows are ")
	b.WriteString("the only thing that decides how an expression reads, which is ")
	b.WriteString("why adding an operator is a row rather than a branch.\n\n")
	pt := ui.NewTable("operator", "precedence", "associativity", "arity")
	for _, op := range shuntingyard.Operators() {
		assoc := "left"
		if op.Right {
			assoc = "right"
		}
		arity := "binary"
		if op.Unary {
			arity = "unary prefix"
		}
		pt.Row("`"+op.Op+"`", strconv.Itoa(op.Prec), assoc, arity)
	}
	b.WriteString(pt.String() + "\n")
	b.WriteString("`u-` and `u+` are the prefix forms. They are separate ")
	b.WriteString("operators rather than a flag on `-` and `+` because they ")
	b.WriteString("take one operand instead of two and sit at a different ")
	b.WriteString("precedence, and conflating the two is how a parser ends up ")
	b.WriteString("reading `-3^2` as `9`.\n\n")

	b.WriteString("## What it refuses\n\n")
	b.WriteString("None of these panics. A realm that evaluates a stored ")
	b.WriteString("expression inside `Render` cannot be made permanently ")
	b.WriteString("unreadable by one bad input, and an expression that would ")
	b.WriteString("wrap `int64` says so instead of returning a plausible wrong ")
	b.WriteString("amount.\n\n")
	rt := ui.NewTable("expression", "error")
	for _, src := range refused {
		_, err := shuntingyard.Eval(src)
		msg := "no error"
		if err != nil {
			msg = err.Error()
		}
		rt.Row("`"+src+"`", ui.Cell(msg))
	}
	b.WriteString(rt.String() + "\n")

	b.WriteString("## Try one\n\n")
	links := make([]string, 0, len(worked))
	for _, w := range worked {
		links = append(links, tryLink(w.expr))
	}
	b.WriteString(strings.Join(links, " · ") + "\n\n")
	b.WriteString("Or append your own: `?e=2*(3+4)`.\n")

	return b.String()
}

// renderOne shows the three stages for one caller-supplied expression.
//
// The raw query string and every error message go through ui.Inline: both can
// carry whatever byte the caller sent, and until they are escaped they are
// attacker-controlled markdown.
//
// Tokens and the RPN do not, and are shown as code spans instead. Tokenize
// accepts a closed alphabet (digits, parentheses and the six operator bytes)
// and rejects everything else, so a token can only ever spell itself. Running
// those through ui.Inline would put a literal backslash inside a code span,
// where markdown does not process escapes, so escaping there makes the page
// wrong rather than safer.
func renderOne(expr string) string {
	var b strings.Builder

	b.WriteString("# Shunting-yard: " + ui.Inline(expr) + "\n\n")
	b.WriteString("[back to the demo](" + selfPath + ")\n\n")

	toks, err := shuntingyard.Tokenize(expr)
	if err != nil {
		b.WriteString("## Rejected while reading it\n\n")
		b.WriteString(ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	b.WriteString("## Tokens\n\n")
	tt := ui.NewTable("#", "kind", "token", "offset")
	for i, tok := range toks {
		tt.Row(strconv.Itoa(i), kindName(tok.Kind), "`"+tok.String()+"`", strconv.Itoa(tok.Pos))
	}
	b.WriteString(tt.OrEmpty("Nothing to tokenize.") + "\n")

	rpn, err := shuntingyard.ToRPN(toks)
	if err != nil {
		b.WriteString("## Rejected while converting it\n\n")
		b.WriteString(ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	b.WriteString("## Reverse Polish notation\n\n")
	b.WriteString("`" + shuntingyard.FormatRPN(rpn) + "`\n\n")

	value, err := shuntingyard.EvalRPN(rpn)
	if err != nil {
		b.WriteString("## Rejected while evaluating it\n\n")
		b.WriteString(ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	b.WriteString("## Value\n\n")
	b.WriteString("`" + strconv.FormatInt(value, 10) + "`\n")

	return b.String()
}

// trace returns the RPN and the value of an expression, as display strings. A
// failure renders as its error, because the refusals are part of the demo.
func trace(expr string) (string, string) {
	toks, err := shuntingyard.Tokenize(expr)
	if err != nil {
		return "", err.Error()
	}
	rpn, err := shuntingyard.ToRPN(toks)
	if err != nil {
		return "", err.Error()
	}
	value, err := shuntingyard.EvalRPN(rpn)
	if err != nil {
		return shuntingyard.FormatRPN(rpn), err.Error()
	}
	return shuntingyard.FormatRPN(rpn), strconv.FormatInt(value, 10)
}

// tryLink builds a link to this realm's own ?e= page.
//
// The escape is not decoration: a '+' in a query string decodes to a space,
// so an unescaped "2+3" would reach the parser as "2 3" and be rejected as
// two numbers in a row.
func tryLink(expr string) string {
	return "[`" + expr + "`](" + selfPath + "?e=" + url.QueryEscape(expr) + ")"
}

// kindName names a token kind for the table.
func kindName(k shuntingyard.Kind) string {
	switch k {
	case shuntingyard.KindNumber:
		return "number"
	case shuntingyard.KindOperator:
		return "operator"
	case shuntingyard.KindLParen:
		return "("
	case shuntingyard.KindRParen:
		return ")"
	}
	return "?"
}
