package importdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRender(t *testing.T) {
	got := Render("")
	expected := `
# [thread] Hello!

## Foo
foo foo foo
## Bar
bar bar bar
`
	uassert.Equal(t, strings.TrimSpace(expected), strings.TrimSpace(got))
}

// Render must not depend on realm state: two calls have to agree, and the
// second must not accumulate the first one's posts.
func TestRenderIsPure(t *testing.T) {
	uassert.Equal(t, Render(""), Render(""))
	uassert.Equal(t, 2, strings.Count(Render(""), "## "))
}

// Posts come back in insertion order. The keys are zero-padded precisely so
// avl's lexicographic ordering does not put "10" before "9" past nine posts.
func TestOrderSurvivesPastNinePosts(t *testing.T) {
	th := newThread("many")
	for i := 0; i < 12; i++ {
		th.addPost(ufmtIdx(i), "body")
	}
	out := th.String()
	// post 9 must appear before post 10
	if strings.Index(out, "## p9\n") > strings.Index(out, "## p10\n") {
		t.Fatalf("insertion order lost past 9 posts:\n%s", out)
	}
	uassert.Equal(t, 12, strings.Count(out, "## "))
}

func ufmtIdx(i int) string {
	return "p" + itoa(i)
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	return string(b)
}
