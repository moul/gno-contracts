package csv

import (
	"strconv"
	"testing"
)

// eq compares two record sets and reports the first position that differs,
// because "want [[a b]] got [[a b]]" with one invisible byte out of place is
// the least useful failure a parser test can produce.
func eq(t *testing.T, got, want [][]string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("record count: got %d, want %d (got %s, want %s)",
			len(got), len(want), dump(got), dump(want))
	}
	for i := range want {
		if len(got[i]) != len(want[i]) {
			t.Fatalf("record %d field count: got %d, want %d (got %s, want %s)",
				i, len(got[i]), len(want[i]), dump(got), dump(want))
		}
		for j := range want[i] {
			if got[i][j] != want[i][j] {
				t.Fatalf("record %d field %d: got %q, want %q",
					i, j, got[i][j], want[i][j])
			}
		}
	}
}

// dump renders a record set as a quoted literal, so a trailing space or a
// stray carriage return is visible in the failure message.
func dump(rs [][]string) string {
	out := "["
	for i, r := range rs {
		if i > 0 {
			out += " "
		}
		out += "["
		for j, f := range r {
			if j > 0 {
				out += " "
			}
			out += strconv.Quote(f)
		}
		out += "]"
	}
	return out + "]"
}

func TestParseBasic(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want [][]string
	}{
		{"one field", "a", [][]string{{"a"}}},
		{"one record", "a,b,c", [][]string{{"a", "b", "c"}}},
		{"two records", "a,b\nc,d", [][]string{{"a", "b"}, {"c", "d"}}},
		{"crlf", "a,b\r\nc,d", [][]string{{"a", "b"}, {"c", "d"}}},
		{"empty fields", "a,,b", [][]string{{"a", "", "b"}}},
		{"empty leading field", ",a", [][]string{{"", "a"}}},
		{"empty trailing field", "a,", [][]string{{"a", ""}}},
		{"spaces are content", " a , b ", [][]string{{" a ", " b "}}},
		{"ragged records are allowed", "a,b,c\nd", [][]string{{"a", "b", "c"}, {"d"}}},
		{"quoted plain", `"a","b"`, [][]string{{"a", "b"}}},
		{"quoted empty", `a,"",b`, [][]string{{"a", "", "b"}}},
		{"mixed quoting", `a,"b",c`, [][]string{{"a", "b", "c"}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(tc.in)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.in, err)
			}
			eq(t, got, tc.want)
		})
	}
}

// TestQuotedFieldHoldsSeparators is the property this package exists for. A
// parser that splits on newlines and then on commas gets every row here
// wrong, and gets it wrong silently: the output is still a rectangle of
// strings, just not the right one.
func TestQuotedFieldHoldsSeparators(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want [][]string
	}{
		{"comma inside quotes", `"a,b",c`, [][]string{{"a,b", "c"}}},
		{"newline inside quotes", "\"line1\nline2\",c", [][]string{{"line1\nline2", "c"}}},
		{"crlf inside quotes is kept verbatim", "\"a\r\nb\"", [][]string{{"a\r\nb"}}},
		{"blank line inside quotes", "\"a\n\nb\"", [][]string{{"a\n\nb"}}},
		{"several commas", `"a,b,c"`, [][]string{{"a,b,c"}}},
		{"quoted field then a real newline", "\"a,b\"\nc", [][]string{{"a,b"}, {"c"}}},
		{"only separators", `",",","`, [][]string{{",", ","}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(tc.in)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.in, err)
			}
			eq(t, got, tc.want)
		})
	}
}

func TestDoubledQuoteIsOneQuote(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want [][]string
	}{
		{"in the middle", `"he said ""hi"""`, [][]string{{`he said "hi"`}}},
		{"whole field", `""""`, [][]string{{`"`}}},
		{"two quotes", `""""""`, [][]string{{`""`}}},
		{"leading", `"""a"`, [][]string{{`"a`}}},
		{"trailing", `"a"""`, [][]string{{`a"`}}},
		{"with a comma", `"a"",""b"`, [][]string{{`a","b`}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(tc.in)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.in, err)
			}
			eq(t, got, tc.want)
		})
	}
}

// TestBareQuoteIsLiteral pins the asymmetry: a quote that opens a field
// quotes it, and a quote anywhere else in an unquoted field is just a
// character. Go's encoding/csv rejects the second; spreadsheets accept it,
// and so does this.
func TestBareQuoteIsLiteral(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want [][]string
	}{
		{"inside", `a"b`, [][]string{{`a"b`}}},
		{"at the end", `ab"`, [][]string{{`ab"`}}},
		{"doubled, not unescaped", `a""b`, [][]string{{`a""b`}}},
		{"after a space", ` "a"`, [][]string{{` "a"`}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(tc.in)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.in, err)
			}
			eq(t, got, tc.want)
		})
	}
}

func TestBlankLinesAndTrailingNewline(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want [][]string
	}{
		{"empty input", "", [][]string{}},
		{"only a newline", "\n", [][]string{}},
		{"only newlines", "\n\n\n", [][]string{}},
		{"trailing newline", "a,b\n", [][]string{{"a", "b"}}},
		{"trailing crlf", "a,b\r\n", [][]string{{"a", "b"}}},
		{"blank line between", "a\n\nb", [][]string{{"a"}, {"b"}}},
		{"leading blank line", "\na", [][]string{{"a"}}},
		{"a quoted empty field is a record", `""`, [][]string{{""}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(tc.in)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.in, err)
			}
			eq(t, got, tc.want)
		})
	}
}

func TestParseRejects(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string // substring the message must carry
	}{
		{"unterminated", `"abc`, "unterminated"},
		{"unterminated empty", `"`, "unterminated"},
		{"unterminated after escape", `"a""`, "unterminated"},
		{"text after closing quote", `"a"b`, "after closing quote"},
		{"space after closing quote", `"a" ,b`, "after closing quote"},
		{"lone cr after closing quote", "\"a\"\rb", "after closing quote"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.in)
			if err == nil {
				t.Fatalf("Parse(%q): want error, got nil", tc.in)
			}
			if !contains(err.Error(), tc.want) {
				t.Fatalf("Parse(%q): message %q does not carry %q", tc.in, err.Error(), tc.want)
			}
		})
	}
}

// TestParseErrorNamesThePosition: an error with no coordinates is an error
// nobody can act on, and a csv file is exactly the input where the position
// is the whole answer.
func TestParseErrorNamesThePosition(t *testing.T) {
	_, err := Parse("a,b\nc,\"d\ne,f")
	if err == nil {
		t.Fatal("want error, got nil")
	}
	if !contains(err.Error(), "record 2") {
		t.Fatalf("message %q does not name record 2", err.Error())
	}
	if !contains(err.Error(), "field 2") {
		t.Fatalf("message %q does not name field 2", err.Error())
	}
}

func TestNeedsQuoting(t *testing.T) {
	cases := []struct {
		name  string
		field string
		want  bool
	}{
		{"plain", "abc", false},
		{"empty", "", false},
		{"spaces", " a ", false},
		{"comma", "a,b", true},
		{"quote", `a"b`, true},
		{"newline", "a\nb", true},
		{"carriage return", "a\rb", true},
		{"only a comma", ",", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := NeedsQuoting(tc.field, ','); got != tc.want {
				t.Fatalf("NeedsQuoting(%q): got %v, want %v", tc.field, got, tc.want)
			}
		})
	}
}

func TestField(t *testing.T) {
	cases := []struct {
		name  string
		field string
		want  string
	}{
		{"plain is untouched", "abc", "abc"},
		{"empty is untouched", "", ""},
		{"comma is quoted", "a,b", `"a,b"`},
		{"quote is doubled", `a"b`, `"a""b"`},
		{"newline is quoted", "a\nb", "\"a\nb\""},
		{"nothing but quotes", `""`, `""""""`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Field(tc.field, ','); got != tc.want {
				t.Fatalf("Field(%q): got %q, want %q", tc.field, got, tc.want)
			}
		})
	}
}

func TestFormat(t *testing.T) {
	cases := []struct {
		name string
		in   [][]string
		want string
	}{
		{"nothing", [][]string{}, ""},
		{"one record", [][]string{{"a", "b"}}, "a,b\n"},
		{"two records", [][]string{{"a"}, {"b"}}, "a\nb\n"},
		{"quotes only where needed", [][]string{{"a", "b,c"}}, "a,\"b,c\"\n"},
		{"empty fields", [][]string{{"", "a", ""}}, ",a,\n"},
		// A record holding one empty field would otherwise render as a blank
		// line, which the parser skips: the record would be lost.
		{"a sole empty field is quoted", [][]string{{""}}, "\"\"\n"},
		{"but not when a sibling follows", [][]string{{"", ""}}, ",\n"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Format(tc.in); got != tc.want {
				t.Fatalf("Format: got %q, want %q", got, tc.want)
			}
		})
	}
}

// TestRoundTrip is the only test here that covers the two halves together,
// and the only one that would have caught the sole-empty-field case: each
// half is defensible on its own and the pair still loses a record.
func TestRoundTrip(t *testing.T) {
	cases := []struct {
		name string
		in   [][]string
	}{
		{"plain", [][]string{{"a", "b"}, {"c", "d"}}},
		{"empties", [][]string{{"", "a"}, {"b", ""}}},
		{"sole empty field", [][]string{{""}}},
		{"two empty fields", [][]string{{"", ""}}},
		{"separators", [][]string{{"a,b", "c\nd", `e"f`}}},
		{"crlf in a field", [][]string{{"a\r\nb"}}},
		{"quotes", [][]string{{`"`, `""`, `a"`}}},
		{"ragged", [][]string{{"a", "b", "c"}, {"d"}}},
		{"spaces", [][]string{{" ", "  a  "}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(Format(tc.in))
			if err != nil {
				t.Fatalf("Parse(Format(%s)): %v", dump(tc.in), err)
			}
			eq(t, got, tc.in)
		})
	}
}

func TestDialectComma(t *testing.T) {
	d := Dialect{Comma: ';'}
	got, err := ParseDialect("a;b,c\nd;e", d)
	if err != nil {
		t.Fatalf("ParseDialect: %v", err)
	}
	eq(t, got, [][]string{{"a", "b,c"}, {"d", "e"}})

	if out := FormatDialect([][]string{{"a;b", "c,d"}}, d); out != "\"a;b\";c,d\n" {
		t.Fatalf("FormatDialect: got %q", out)
	}
}

func TestDialectComment(t *testing.T) {
	d := Dialect{Comment: '#'}
	got, err := ParseDialect("# a header\na,b\n#skip\nc,d", d)
	if err != nil {
		t.Fatalf("ParseDialect: %v", err)
	}
	eq(t, got, [][]string{{"a", "b"}, {"c", "d"}})

	// Only at the start of a line, and never inside a quoted field.
	got, err = ParseDialect("a,#b\n\"#c\",d", d)
	if err != nil {
		t.Fatalf("ParseDialect: %v", err)
	}
	eq(t, got, [][]string{{"a", "#b"}, {"#c", "d"}})
}

// TestDialectCommentRoundTrip: the writer has to know the comment byte or it
// emits a record the reader will silently drop. Quoting is positional here,
// which is why Field alone cannot decide it.
func TestDialectCommentRoundTrip(t *testing.T) {
	d := Dialect{Comment: '#'}
	in := [][]string{{"#1", "x"}, {"a", "#2"}}
	out := FormatDialect(in, d)
	if out != "\"#1\",x\na,#2\n" {
		t.Fatalf("FormatDialect: got %q", out)
	}
	got, err := ParseDialect(out, d)
	if err != nil {
		t.Fatalf("ParseDialect(%q): %v", out, err)
	}
	eq(t, got, in)
}

func TestDialectStrict(t *testing.T) {
	d := Dialect{Strict: true}
	if _, err := ParseDialect("a,b\nc", d); err == nil {
		t.Fatal("ragged input under Strict: want error, got nil")
	} else if !contains(err.Error(), "record 2") {
		t.Fatalf("message %q does not name record 2", err.Error())
	}
	got, err := ParseDialect("a,b\nc,d", d)
	if err != nil {
		t.Fatalf("ParseDialect: %v", err)
	}
	eq(t, got, [][]string{{"a", "b"}, {"c", "d"}})
}

func TestDialectCRLF(t *testing.T) {
	if got := FormatDialect([][]string{{"a", "b"}}, Dialect{CRLF: true}); got != "a,b\r\n" {
		t.Fatalf("FormatDialect: got %q", got)
	}
}

func TestDialectRejects(t *testing.T) {
	cases := []struct {
		name string
		d    Dialect
	}{
		{"quote as separator", Dialect{Comma: '"'}},
		{"newline as separator", Dialect{Comma: '\n'}},
		{"carriage return as separator", Dialect{Comma: '\r'}},
		{"comment equals separator", Dialect{Comma: ';', Comment: ';'}},
		{"quote as comment", Dialect{Comment: '"'}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := ParseDialect("a,b", tc.d); err == nil {
				t.Fatalf("ParseDialect with %+v: want error, got nil", tc.d)
			}
		})
	}
}

// contains is strings.Contains, written out so the test file needs no import
// beyond testing and strconv.
func contains(s, sub string) bool {
	if len(sub) == 0 {
		return true
	}
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
