// Package lazy is version 0 of the "lazy migration" upgrade pattern
// (pattern D of the exploration; see ../README.md).
//
// This version is an ordinary record store. It is written without any
// knowledge of a successor: what makes the pattern work is only that its
// records are readable from outside, which any avl-backed realm already is.
package lazy

import (
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Record is v0's shape. v1 changes it, which is the whole reason for a new
// version: a stored-layout change is never done in place.
type Record struct {
	Name  string
	Score int
}

func (r *Record) String() string {
	if r == nil {
		return "nil"
	}
	return ufmt.Sprintf("v0{%s %d}", r.Name, r.Score)
}

var records = avl.NewTree()

func init() {
	records.Set("ada", &Record{Name: "ada", Score: 1})
	records.Set("bob", &Record{Name: "bob", Score: 2})
}

// Get returns a record or nil. Non-crossing: v1 reads through it while
// migrating, and gnoweb can call it without a transaction.
func Get(key string) *Record {
	v := records.Get(key)
	if v == nil {
		return nil
	}
	return v.(*Record)
}

// Size is how many records still live here. It never shrinks: lazy migration
// COPIES forward, it does not move, so v0 keeps paying for every record it
// ever held.
func Size() int {
	return records.Size()
}

func Render(_ string) string {
	out := ufmt.Sprintf("lazy/v0: %d records\n", records.Size())
	records.Iterate("", "", func(k string, v any) bool {
		out += ufmt.Sprintf("- %s: %s\n", k, v.(*Record).String())
		return false
	})
	return out
}
