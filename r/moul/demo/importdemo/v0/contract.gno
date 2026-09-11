// Package importdemo shows a realm importing and composing packages from
// ANOTHER namespace — the whole point of the demo.
//
// v2 imported gno.land/p/archive/dom, which is published on no chain we target
// (absent on both sapphire and pearl), so it type-checked locally but could
// never be deployed: `addpkg` failed with
// `could not import gno.land/p/archive/dom (unknown import path)`. v2 is
// archived (`ignore = true`); this version rebuilds the same thread-of-posts
// idea on foreign packages that are actually on chain — `p/nt/avl/v0` for
// ordered storage and `p/nt/ufmt/v0` for formatting.
//
// Deliberately keeps no realm state: Render builds the thread on each call, so
// output depends only on the code and the demo is reproducible.
package importdemo

import (
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// thread is a titled list of posts, kept in an avl.Tree so iteration is ordered
// by key rather than by insertion — the same guarantee the realm needs for a
// stable Render.
type thread struct {
	name  string
	posts *avl.Tree // zero-padded index -> *post
	n     int
}

type post struct {
	title string
	body  string
}

func newThread(name string) *thread {
	return &thread{name: name, posts: avl.NewTree()}
}

// addPost appends a post. The key is zero-padded so avl's lexicographic order
// matches insertion order past 9 entries ("10" would otherwise sort before "9").
func (t *thread) addPost(title, body string) {
	t.posts.Set(padIdx(t.n), &post{title: title, body: body})
	t.n++
}

// padIdx renders i as a fixed-width, zero-padded key.
//
// Done by hand on purpose: gno's ufmt supports NO width or padding flags, so
// ufmt.Sprintf("%03d", 7) yields "7", not "007" — silently, with no error. Keys
// built that way sort as "0","1","10","11","2", which quietly reorders every
// thread past nine posts (TestOrderSurvivesPastNinePosts covers exactly this).
func padIdx(i int) string {
	s := strconv.Itoa(i)
	for len(s) < 3 {
		s = "0" + s
	}
	return s
}

// String renders the thread as Markdown.
func (t *thread) String() string {
	var b strings.Builder
	b.WriteString(ufmt.Sprintf("# [thread] %s\n\n", t.name))
	t.posts.Iterate("", "", func(_ string, v any) bool {
		p := v.(*post)
		b.WriteString(ufmt.Sprintf("## %s\n%s\n", p.title, p.body))
		return false
	})
	return b.String()
}

// Render renders the demo thread for gnoweb.
func Render(path string) string {
	t := newThread("Hello!")
	t.addPost("Foo", "foo foo foo")
	t.addPost("Bar", "bar bar bar")
	return t.String()
}
