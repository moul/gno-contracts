package usernames

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	tb "gno.land/p/moul/toolbox/v0"
	"gno.land/r/sys/users"
)

// hubURL is the toolbox this tool belongs to. A private realm cannot import
// the hub, so the link is a constant on this side; `r/moul/toolbox` holds the
// authoritative copy and its tests check that the tool path matches.
const hubURL = "/r/moul/toolbox"

// maxInput bounds what is echoed back into the page. A render that reflects an
// unbounded query parameter is a page anyone can make arbitrarily large.
const maxInput = 64

// Render routes gnoweb paths:
//
//	/                the form, and what the tool answers
//	/lookup?q=moul   the result, which is where the form submits
//	/moul            the same result, addressable directly
//	/g1manfred...    the same, by address
func Render(path string) string {
	req := realmpath.Parse(path)
	parts := req.PathParts()

	input := req.Query.Get("q")
	if input == "" && len(parts) == 1 && parts[0] != "" && parts[0] != "lookup" {
		input = parts[0]
	}
	if len(parts) > 1 {
		return header() + "\n" + notFound(strings.Join(parts, "/"))
	}
	if input == "" {
		return header() + "\n" + renderHome()
	}
	return header() + "\n" + renderResult(input)
}

func header() string {
	return tb.Nav(hubURL, "Usernames")
}

func renderHome() string {
	var b strings.Builder
	b.WriteString(md.H1("Usernames"))
	b.WriteString("\nWho holds a name, and what name an address holds. Type either one.\n")
	b.WriteString("\n" + form())
	b.WriteString("\n" + md.H2("What this answers"))
	b.WriteString("\n" + md.BulletList([]string{
		"The address behind a username, and the username behind an address.",
		"Whether the name you typed is their **current** name or one they renamed away from.",
		"The canonical key the name collapses to, and who already holds that key.",
	}))
	b.WriteString("\n" + md.H2("The same thing from a terminal"))
	b.WriteString("\nThis page is " + md.InlineCode("r/sys/users") +
		" read through " + md.InlineCode("vm/qeval") + ", with the follow-up questions already asked:\n")
	b.WriteString("\n" + md.LanguageCodeBlock("sh", qevalCommand("moul")))
	b.WriteString("\nTry " + md.Link("moul", "/r/moul/toolbox/usernames:moul") +
		", or paste an address into the box above.\n")
	return b.String()
}

func renderResult(input string) string {
	var b strings.Builder
	shown := ui.Inline(trim(input))
	b.WriteString(md.H1("Usernames"))
	b.WriteString("\n" + form())

	data := lookup(input)
	if data == nil {
		b.WriteString("\n" + notFound(input))
		return b.String()
	}

	t := ui.NewTable("Field", "Value")
	t.Row("Username", data.RenderLink(""))
	t.Row("Address", ui.AddrFull(data.Addr()))
	if current := CurrentName(input); current != "" {
		t.Row("Note", "You asked for "+md.InlineCode(shown)+
			", which is an earlier name. The current one is "+md.InlineCode(ui.Inline(current))+".")
	}
	t.Row("Canonical", md.InlineCode(ui.Inline(users.Canonicalize(data.Name()))))
	b.WriteString("\n" + t.String())

	if cmd := qevalCommand(input); cmd != "" {
		b.WriteString("\n" + md.LanguageCodeBlock("sh", cmd))
	}
	return b.String()
}

func notFound(input string) string {
	var b strings.Builder
	b.WriteString("Nothing registered under " + md.InlineCode(ui.Inline(trim(input))) + ".\n")
	b.WriteString("\n" + md.BulletList(notFoundHints(input)))
	return b.String()
}

// notFoundHints says what "not found" means for this particular input, which
// is three different things.
func notFoundHints(input string) []string {
	trimmed := trim(input)
	if address(trimmed).IsValid() {
		return []string{
			"That is a valid address, so it exists on chain. It has no username.",
			"Register one at " + md.Link("r/gnoland/users", "/r/gnoland/users"),
		}
	}
	hints := []string{
		"Nobody holds it, or the account was deleted: a deleted name keeps its tombstone and resolves to nothing.",
	}
	if owner := CanonicalOwner(trimmed); owner != "" {
		hints = append(hints, "A lookalike is taken: "+md.InlineCode(ui.Inline(owner))+
			" already holds the canonical key "+md.InlineCode(ui.Inline(users.Canonicalize(trimmed)))+".")
	} else if Taken(trimmed) {
		hints = append(hints, "The name IS taken, by an account that was deleted or renamed. Registering it would still fail.")
	}
	return hints
}

func form() string {
	return tb.NewQuery("lookup").Field("q", "username or g1 address").String()
}

// qevalCommand is the CLI call this page is the equivalent of, with the input
// substituted. It returns "" for an input that cannot be put inside a fenced
// code block safely: nothing escapes inside a fence, so the only safe move is
// not to print one.
func qevalCommand(input string) string {
	arg := trim(input)
	if !safeArg(arg) {
		return ""
	}
	return "gnokey query vm/qeval -remote https://rpc.gno.land \\\n" +
		"  -data 'gno.land/r/moul/toolbox/usernames.Resolve(\"" + arg + "\")'"
}

// safeArg reports whether s can be interpolated into a shell single-quoted
// string inside a markdown code fence. Usernames and addresses are both well
// inside this set, so a refusal only ever hides the hint, never an answer.
func safeArg(s string) bool {
	if s == "" || len(s) > maxInput {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z':
		case c >= 'A' && c <= 'Z':
		case c >= '0' && c <= '9':
		case c == '_' || c == '-' || c == '.':
		default:
			return false
		}
	}
	return true
}

// trim bounds an echoed input. Everything downstream escapes it; this only
// stops one query from rendering a page of arbitrary size.
func trim(s string) string {
	if len(s) > maxInput {
		return s[:maxInput] + "…"
	}
	return s
}
