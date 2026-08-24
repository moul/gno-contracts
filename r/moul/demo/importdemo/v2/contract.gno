package importdemo

import (
	"gno.land/p/archive/dom"
)

func Render(path string) string {
	thread := dom.Plot{Name: "Hello!"}
	thread.AddPost("Foo", "foo foo foo")
	thread.AddPost("Bar", "bar bar bar")
	return thread.String()
}
