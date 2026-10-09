package toolbox

import "strings"

// Query builds the gnoweb form a read-only tool needs: a text box whose
// submission navigates to one of the realm's own Render paths, with the typed
// values as query parameters.
//
// This is the "template of a query" a toolbox page is for. Rendered by gnoweb,
//
//	NewQuery("lookup").Field("q", "username or g1 address").String()
//
// posts to the realm and redirects to `/r/moul/toolbox/usernames/v0:lookup?q=moul`
// (`gno.land/pkg/gnoweb/handler_http.go`, `Post`: the `path` attribute travels
// as the hidden `__gno_path` field and becomes the render args, every other
// field becomes a query parameter). Nothing is signed and no transaction is
// built: the result is a `Render` call, which is exactly what
// `gnokey query vm/qrender` would have done from a terminal.
//
// A form whose fields should CALL a function instead is a different element,
// `<gno-form exec="Fn">`, and it is not what this type builds. A query form is
// free and a call is not, so the two are deliberately not one constructor with
// a flag.
type Query struct {
	path   string
	fields []queryField
}

type queryField struct {
	name        string
	placeholder string
}

// NewQuery starts a form submitting to the Render path args.
//
// Pass "" to submit to the realm's root page. Do not include a leading colon
// or the realm path itself: gnoweb supplies both, and a value that looks like
// a URL is percent-encoded into one path element rather than followed.
func NewQuery(path string) *Query {
	return &Query{path: path}
}

// Field adds a text input. name is the query parameter the realm will read;
// placeholder is the grey text in the empty box.
//
// A field with an empty name is ignored: gnoweb rejects the whole form for it,
// and losing one input beats losing the page.
func (q *Query) Field(name, placeholder string) *Query {
	if name == "" {
		return q
	}
	q.fields = append(q.fields, queryField{name: name, placeholder: placeholder})
	return q
}

// Len is how many fields the form carries.
func (q *Query) Len() int { return len(q.fields) }

// String renders the form as the markdown-embedded HTML gnoweb parses.
//
// A form with no field renders as the empty string rather than as a submit
// button with nothing to submit.
func (q *Query) String() string {
	if len(q.fields) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString(`<gno-form`)
	if q.path != "" {
		b.WriteString(` path="` + attr(q.path) + `"`)
	}
	b.WriteString(">\n")
	for _, f := range q.fields {
		b.WriteString(`<gno-input name="` + attr(f.name) + `" type="text"`)
		if f.placeholder != "" {
			b.WriteString(` placeholder="` + attr(f.placeholder) + `"`)
		}
		b.WriteString(" />\n")
	}
	b.WriteString("</gno-form>\n")
	return b.String()
}

// attr escapes a value for an HTML attribute in double quotes.
//
// gnoweb parses these with a real HTML tokenizer, so an unescaped quote does
// not merely look wrong: it ends the attribute and whatever follows becomes
// further attributes of the same tag. Ampersand first, or the escapes of the
// later replacements would themselves be escaped.
func attr(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, `"`, "&quot;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}
