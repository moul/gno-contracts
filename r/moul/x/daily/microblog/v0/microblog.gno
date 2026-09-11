// Package microblog is a public microblog wall for gno.land.
//
// Anyone can Post a short message (<= maxMsgLen chars). Every post records
// the caller address, the message, and the block height at which it was made.
// Render displays the wall newest-first, 20 posts per page, with pagination
// driven by the Render path (e.g. "?page=2" or "/2").
package microblog

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
)

// maxMsgLen is the maximum length (in bytes) of a single post.
const maxMsgLen = 280

// pageSize is how many posts a single Render page shows.
const pageSize = 20

// post is a single microblog entry.
type post struct {
	Author string // bech32 address of the poster
	Msg    string // the message body
	Height int64  // block height at which it was posted
}

// posts is the append-only wall, in chronological (oldest-first) order.
// Render reverses this view to show newest-first.
var posts []post

// Post publishes msg to the wall. It is a crossing function: callers invoke it
// with Post(cross(cur), "hello"). It panics if msg is empty or longer than
// maxMsgLen bytes.
func Post(cur realm, msg string) {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	if len(msg) == 0 {
		panic("microblog: empty message")
	}
	if len(msg) > maxMsgLen {
		panic("microblog: message too long (max " + strconv.Itoa(maxMsgLen) + " bytes)")
	}

	author := unsafe.PreviousRealm().Address()

	posts = append(posts, post{
		Author: author.String(),
		Msg:    msg,
		Height: runtime.ChainHeight(),
	})

	chain.Emit("Post", "author", author.String(), "len", strconv.Itoa(len(msg)))
}

// Count returns the total number of posts on the wall.
func Count() int {
	return len(posts)
}

// Render renders the wall as Markdown, newest-first, pageSize posts per page.
// The page is parsed from path: "?page=N", "?p=N", "/N", or a bare "N" all
// select page N (1-indexed). Anything else defaults to page 1.
func Render(path string) string {
	total := len(posts)
	page := parsePage(path)

	var b strings.Builder
	b.WriteString("# Microblog Wall\n\n")

	if total == 0 {
		b.WriteString("_No posts yet. Be the first to post._\n")
		return b.String()
	}

	pages := (total + pageSize - 1) / pageSize
	if page < 1 {
		page = 1
	}
	if page > pages {
		page = pages
	}

	b.WriteString(strconv.Itoa(total))
	b.WriteString(" posts total · page ")
	b.WriteString(strconv.Itoa(page))
	b.WriteString(" of ")
	b.WriteString(strconv.Itoa(pages))
	b.WriteString("\n\n")

	// Newest-first: post index total-1 is newest. For page p (1-indexed),
	// skip (p-1)*pageSize newest posts, then take up to pageSize.
	start := total - 1 - (page-1)*pageSize
	end := start - pageSize + 1
	if end < 0 {
		end = 0
	}

	for i := start; i >= end; i-- {
		p := posts[i]
		b.WriteString("- **")
		b.WriteString(shortAddr(p.Author))
		b.WriteString("** · height ")
		b.WriteString(strconv.FormatInt(p.Height, 10))
		b.WriteString("\n\n  ")
		b.WriteString(escapeInline(p.Msg))
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(renderNav(page, pages))
	return b.String()
}

// renderNav builds a simple prev/next navigation footer as Markdown links.
func renderNav(page, pages int) string {
	var b strings.Builder
	if page > 1 {
		b.WriteString("[← newer](?page=")
		b.WriteString(strconv.Itoa(page - 1))
		b.WriteString(")")
	}
	if page > 1 && page < pages {
		b.WriteString(" · ")
	}
	if page < pages {
		b.WriteString("[older →](?page=")
		b.WriteString(strconv.Itoa(page + 1))
		b.WriteString(")")
	}
	if b.Len() == 0 {
		return ""
	}
	return b.String() + "\n"
}

// parsePage extracts the 1-indexed page number from a Render path. It accepts
// "?page=N", "?p=N", "/N", and a bare "N". Unrecognized input yields page 1.
func parsePage(path string) int {
	path = strings.TrimSpace(path)
	if path == "" {
		return 1
	}

	// Query form: "?page=2&foo=bar" or "?p=2".
	if idx := strings.IndexByte(path, '?'); idx >= 0 {
		query := path[idx+1:]
		for _, part := range strings.Split(query, "&") {
			kv := strings.SplitN(part, "=", 2)
			if len(kv) != 2 {
				continue
			}
			if kv[0] == "page" || kv[0] == "p" {
				if n, err := strconv.Atoi(strings.TrimSpace(kv[1])); err == nil {
					return n
				}
			}
		}
		return 1
	}

	// Path form: "/2" or "2".
	seg := strings.TrimPrefix(path, "/")
	if n, err := strconv.Atoi(seg); err == nil {
		return n
	}
	return 1
}

// shortAddr abbreviates a bech32 address for display: g1abcd…wxyz.
func shortAddr(addr string) string {
	if len(addr) <= 12 {
		return addr
	}
	return addr[:6] + "…" + addr[len(addr)-4:]
}

// escapeInline neutralizes characters that would break the Markdown list item
// layout (newlines collapse to spaces; leading markers are defused).
func escapeInline(s string) string {
	s = strings.ReplaceAll(s, "\r\n", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.ReplaceAll(s, "\r", " ")
	return s
}
