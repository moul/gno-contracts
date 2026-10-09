package toolbox

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestQueryString(t *testing.T) {
	got := NewQuery("lookup").Field("q", "username or g1 address").String()
	want := "<gno-form path=\"lookup\">\n" +
		"<gno-input name=\"q\" type=\"text\" placeholder=\"username or g1 address\" />\n" +
		"</gno-form>\n"
	uassert.Equal(t, want, got)
}

func TestQueryNoPathNoPlaceholder(t *testing.T) {
	got := NewQuery("").Field("q", "").String()
	want := "<gno-form>\n<gno-input name=\"q\" type=\"text\" />\n</gno-form>\n"
	uassert.Equal(t, want, got)
}

func TestQueryTwoFields(t *testing.T) {
	q := NewQuery("compare").Field("a", "first").Field("b", "second")
	uassert.Equal(t, 2, q.Len())
	got := q.String()
	uassert.True(t, strings.Contains(got, `name="a"`))
	uassert.True(t, strings.Contains(got, `name="b"`))
	uassert.Equal(t, 1, strings.Count(got, "<gno-form"))
}

// TestQueryEmptyRendersNothing: a form with no input is a submit button with
// nothing to submit, so it is not rendered at all.
func TestQueryEmptyRendersNothing(t *testing.T) {
	uassert.Equal(t, "", NewQuery("lookup").String())
	uassert.Equal(t, "", NewQuery("lookup").Field("", "ignored").String())
}

// TestQueryEscapesAttributes: gnoweb parses these with a real HTML tokenizer,
// so an unescaped quote ends the attribute and everything after it becomes
// further attributes of the same tag.
func TestQueryEscapesAttributes(t *testing.T) {
	got := NewQuery(`a"b`).Field("q", `<script>&"`).String()
	uassert.True(t, strings.Contains(got, `path="a&quot;b"`))
	uassert.True(t, strings.Contains(got, `placeholder="&lt;script&gt;&amp;&quot;"`))
	uassert.False(t, strings.Contains(got, "<script>"))
}

func TestAttr(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain", "username", "username"},
		{"quote", `a"b`, "a&quot;b"},
		{"ampersand", "a&b", "a&amp;b"},
		{"angle", "<b>", "&lt;b&gt;"},
		{"ampersand before quote", `&"`, "&amp;&quot;"},
		{"already escaped stays literal", "&amp;", "&amp;amp;"},
		{"empty", "", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, attr(tc.in))
		})
	}
}
