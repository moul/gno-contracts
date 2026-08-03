// PKGPATH: gno.land/r/moul/main

package main

import (
	"testing"

	"gno.land/r/moul/home/v2"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm("g1manfred47kzduec920z88wfr64ylksmdcedlf5"))
	home.AddNewTodo(cross(cur), "aaa")
	home.AddNewTodo(cross(cur), "bbb")
	home.AddNewTodo(cross(cur), "ccc")
	home.AddNewTodo(cross(cur), "ddd")
	home.AddNewTodo(cross(cur), "eee")
	home.UpdateStatus(cross(cur), "Lorem Ipsum")
	home.DeleteTodo(cross(cur), 3)
	println(home.Render(""))
}

// Output:
// # Manfred's (gn)home Dashboard
//
// ## Meme
// ![](https://i.imgflip.com/7ze8dc.jpg)
//
// ## Status
// Lorem Ipsum
//
// ## Personal ToDo List
// - [ ] fill this todo list...
// - [ ] aaa
// - [ ] bbb
// - [ ] ddd
// - [ ] eee
