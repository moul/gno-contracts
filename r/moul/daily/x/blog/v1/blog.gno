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

	"gno.land/p/nt/avl/v0"
)

// Post is a single blog entry.
type Post struct {
	ID     int
	Title  string
	Body   string
	Author address
	Height int64
}

// posts holds every published post keyed by its zero-padded id (for
// deterministic ordering) and nextID is the id assigned to the next post.
var (
	posts  avl.Tree // key: zero-padded id string -> *Post
	nextID int
)

// key returns a fixed-width, zero-padded key so avl.Tree iteration is ordered
// by numeric id (and thus by publication order).
func key(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

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

	id := nextID
	nextID++

	p := &Post{
		ID:     id,
		Title:  title,
		Body:   body,
		Author: unsafe.PreviousRealm().Address(),
		Height: runtime.ChainHeight(),
	}
	posts.Set(key(id), p)

	chain.Emit(
		"PostPublished",
		"id", strconv.Itoa(id),
		"author", p.Author.String(),
	)
	return id
}

// PostCount returns the number of published posts.
func PostCount() int {
	return posts.Size()
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
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return "# Not found\n\nInvalid post path: `" + path + "`\n\n[← back](/r/REPLACE_ADDR/blog)\n"
	}
	v, ok := posts.Get(key(id))
	if !ok {
		return "# Not found\n\nNo post with id " + idStr + ".\n\n[← back](/r/REPLACE_ADDR/blog)\n"
	}
	return renderPost(v.(*Post))
}

func renderList() string {
	var b strings.Builder
	b.WriteString("# 📝 Blog\n\n")
	if posts.Size() == 0 {
		b.WriteString("_No posts yet. Be the first to `Publish`._\n")
		return b.String()
	}
	b.WriteString(strconv.Itoa(posts.Size()) + " post(s), newest first.\n\n")

	// avl iterates ascending; iterate in reverse for newest-first.
	posts.ReverseIterate("", "", func(_ string, v interface{}) bool {
		p := v.(*Post)
		b.WriteString("## [")
		b.WriteString(p.Title)
		b.WriteString("](/r/REPLACE_ADDR/blog:/")
		b.WriteString(strconv.Itoa(p.ID))
		b.WriteString(")\n\n")
		b.WriteString("by `")
		b.WriteString(p.Author.String())
		b.WriteString("` · height ")
		b.WriteString(strconv.FormatInt(p.Height, 10))
		b.WriteString("\n\n")
		b.WriteString(snippet(p.Body))
		b.WriteString("\n\n---\n\n")
		return false
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
