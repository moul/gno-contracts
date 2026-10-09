package toolbox

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
)

// Index renders a catalog as a markdown table: tool, what it does, tags.
//
// Every cell that came from a [Tool] is escaped exactly once, with the helper
// for the slot it lands in. A tool description is written by whoever wrote the
// entry, which in a hub that accepts runtime registration is not necessarily
// whoever owns the hub, and a pipe or a backtick in one would otherwise
// rewrite the table around it.
//
// The title link is built by hand rather than with [md.Link], which is the one
// place the obvious call is wrong: md.Link runs its text through
// sanitize.InlineText itself, so md.Link(ui.Cell(title), url) escapes twice and
// a title with an asterisk in it renders as a backslash. The slot here is link
// text INSIDE a table cell, and the helper for that is [ui.Cell] (InlineText
// plus the pipe escape InlineText deliberately leaves alone), with the URL
// escaped once by [md.EscapeURL].
func Index(tools []Tool) string {
	t := ui.NewTable("Tool", "What it does", "Tags")
	for _, tool := range tools {
		t.Row(
			"["+ui.Cell(tool.Title)+"]("+md.EscapeURL(tool.URL())+")",
			ui.Cell(tool.Desc),
			ui.Cell(strings.Join(tool.Tags, ", ")),
		)
	}
	return t.OrEmpty("No tools yet.")
}

// Card renders one tool on its own: the title as a link, the description, the
// package path, and the two ways to reach it.
func Card(tool Tool) string {
	var b strings.Builder
	b.WriteString(md.H2(ui.Inline(tool.Title)))
	if tool.Desc != "" {
		b.WriteString("\n" + ui.Inline(tool.Desc) + "\n")
	}
	b.WriteString("\n" + md.BulletList([]string{
		"Open: " + md.Link(tool.URL(), tool.URL()),
		"Path: " + md.InlineCode(tool.Path),
	}))
	if len(tool.Tags) > 0 {
		b.WriteString("\nTags: " + ui.Inline(strings.Join(tool.Tags, ", ")) + "\n")
	}
	return b.String()
}

// Nav renders the one line every tool page carries above its content: a link
// back to the hub, then the tool's own title.
//
// hubURL is a gnoweb path ("/r/moul/toolbox"), not a package path. A tool
// cannot import the hub to ask, so it states it, and this is the one place the
// two have to agree.
func Nav(hubURL, title string) string {
	return md.Link("toolbox", hubURL) + " / " + md.Bold(ui.Inline(title)) + "\n"
}
