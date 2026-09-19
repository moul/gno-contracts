// Package blog is a multi-author on-chain blog realm for gno.land.
//
// Any caller can Publish a post; posts are stored persistently and rendered
// newest-first. Each post records its author (the calling address) and the
// block height at which it was published.
package blog

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/kit/store/v0"
)

// Post is a single blog entry. It carries no id field: the id belongs to the
// store, which hands it back on lookup and iteration.
type Post struct {
	Title  string
	Body   string
	Author address
	Height int64
}

// posts holds every published post. The store keys by seqid, so iteration is
// in publication order for any number of posts; v0 kept its own nextID plus a
// key() that zero-padded to width 12 and stopped ordering past it.
var posts = store.Named("post")

// Publish creates a new post authored by the caller and returns its id.
// It is a state-mutating exported function, so it takes `cur realm`.
func Publish(cur realm, title string, body string) int {
	title = strings.TrimSpace(title)
	body = strings.TrimSpace(body)
	if title == "" {
		panic("blog: title must not be empty")
	}
	if body == "" {
		panic("blog: body must not be empty")
	}

	author := unsafe.PreviousRealm().Address()
	id := posts.Add(&Post{
		Title:  title,
		Body:   body,
		Author: author,
		Height: runtime.ChainHeight(),
	})

	chain.Emit(
		"PostPublished",
		"id", id.String(),
		"author", author.String(),
	)
	return int(id)
}

// PostCount returns the number of published posts.
func PostCount() int {
	return posts.Len()
}

// snippet returns a short one-line preview of the body.
func snippet(body string) string {
	// collapse newlines so the preview stays on a single markdown line
	s := strings.ReplaceAll(body, "\n", " ")
	s = strings.TrimSpace(s)
	const max = 140
	if len(s) > max {
		return s[:max] + "…"
	}
	return s
}

// Render lists all posts newest-first at the root, or a single post's full
// text at path "/<id>". Render is NOT a crossing function.
func Render(path string) string {
	path = strings.TrimSpace(path)
	if path == "" || path == "/" {
		return renderList()
	}
	idStr := strings.TrimPrefix(path, "/")
	id, ok := store.ParseID(idStr)
	if !ok {
		return "# Not found\n\nInvalid post path: `" + path + "`\n\n[← back](/r/REPLACE_ADDR/blog)\n"
	}
	v, ok := posts.Get(id)
	if !ok {
		return "# Not found\n\nNo post with id " + idStr + ".\n\n[← back](/r/REPLACE_ADDR/blog)\n"
	}
	return renderPost(v.(*Post))
}

func renderList() string {
	var b strings.Builder
	b.WriteString("# 📝 Blog\n\n")
	if posts.Len() == 0 {
		b.WriteString("_No posts yet. Be the first to `Publish`._\n")
		return b.String()
	}
	b.WriteString(strconv.Itoa(posts.Len()) + " post(s), newest first.\n\n")

	// Ids ascend with publication, so reverse iteration is newest-first.
	posts.EachReverse(func(id store.ID, v any) {
		p := v.(*Post)
		b.WriteString("## [")
		b.WriteString(p.Title)
		b.WriteString("](/r/REPLACE_ADDR/blog:/")
		b.WriteString(id.String())
		b.WriteString(")\n\n")
		b.WriteString("by `")
		b.WriteString(p.Author.String())
		b.WriteString("` · height ")
		b.WriteString(strconv.FormatInt(p.Height, 10))
		b.WriteString("\n\n")
		b.WriteString(snippet(p.Body))
		b.WriteString("\n\n---\n\n")
	})
	return b.String()
}

func renderPost(p *Post) string {
	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(p.Title)
	b.WriteString("\n\n")
	b.WriteString("by `")
	b.WriteString(p.Author.String())
	b.WriteString("` · height ")
	b.WriteString(strconv.FormatInt(p.Height, 10))
	b.WriteString("\n\n")
	b.WriteString(p.Body)
	b.WriteString("\n\n---\n\n[← back to all posts](/r/REPLACE_ADDR/blog)\n")
	return b.String()
}
