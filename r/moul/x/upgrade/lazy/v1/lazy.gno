// Package lazy is version 1 of the "lazy migration" upgrade pattern
// (pattern D of the exploration; see ../README.md).
//
// v1 changes the stored shape (Score widens, Active is new) and migrates one
// record at a time, on first touch, paid for by whoever touched it. There is
// no migration transaction and no pause.
//
// The catch on today's gno: migrating on read MUTATES, so the read path has to
// be a crossing function. Get therefore costs a transaction and is invisible to
// vm/qeval and to Render. Peek is the honest read-only half, and it reports the
// pre-migration answer for records that have not been touched yet.
package lazy

import (
	v0 "gno.land/r/moul/x/upgrade/lazy/v0"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Record is v1's shape: Score widened to int64 and scaled by 1000, plus a new
// Active flag that migrated records get set to true.
type Record struct {
	Name   string
	Score  int64
	Active bool
}

func (r *Record) String() string {
	if r == nil {
		return "nil"
	}
	return ufmt.Sprintf("v1{%s %d %t}", r.Name, r.Score, r.Active)
}

var records = avl.NewTree()

func init() {
	records.Set("cyd", &Record{Name: "cyd", Score: 3000, Active: true})
}

// migrate converts a v0 record into a v1 one. Kept separate from Get so the
// conversion is testable without a write.
func migrate(old *v0.Record) *Record {
	return &Record{
		Name:   old.Name + "-migrated",
		Score:  int64(old.Score) * 1000,
		Active: true,
	}
}

// Get returns a record, migrating it from v0 on first touch.
//
// Crossing, because the migration writes. That is the cost of the pattern: the
// cheapest possible read is now a transaction.
func Get(cur realm, key string) *Record {
	if v := records.Get(key); v != nil {
		return v.(*Record)
	}
	old := v0.Get(key)
	if old == nil {
		return nil
	}
	r := migrate(old)
	records.Set(key, r)
	return r
}

// Peek is the read-only half: it never migrates, so a record that has not been
// touched yet reads as its v0 self converted on the fly and NOT stored.
func Peek(key string) *Record {
	if v := records.Get(key); v != nil {
		return v.(*Record)
	}
	if old := v0.Get(key); old != nil {
		return migrate(old)
	}
	return nil
}

// Migrated is how many records have actually moved over.
func Migrated() int {
	return records.Size()
}

// Pending is how many v0 records have never been touched. It is only a bound:
// v0 keeps every record it ever had, migrated or not.
func Pending() int {
	n := 0
	for _, k := range []string{"ada", "bob"} {
		if records.Get(k) == nil && v0.Get(k) != nil {
			n++
		}
	}
	return n
}

func Render(_ string) string {
	out := ufmt.Sprintf("lazy/v1: %d migrated, %d pending in v0\n", Migrated(), Pending())
	records.Iterate("", "", func(k string, v any) bool {
		out += ufmt.Sprintf("- %s: %s\n", k, v.(*Record).String())
		return false
	})
	return out
}
