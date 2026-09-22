package ulist

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// countNodes walks the tree directly, so the tests assert against the real
// structure rather than against Compact's own bookkeeping.
func countNodes(n *treeNode) int {
	if n == nil {
		return 0
	}
	return 1 + countNodes(n.left) + countNodes(n.right)
}

func TestCompactEmptyAndNil(t *testing.T) {
	var nilList *List
	uassert.Equal(t, 0, nilList.Compactable())
	uassert.Equal(t, 0, nilList.Compact())

	l := New()
	uassert.Equal(t, 0, l.Compactable())
	uassert.Equal(t, 0, l.Compact())
}

func TestCompactNothingDeleted(t *testing.T) {
	l := New()
	l.Append(generateSequence(20)...)
	before := countNodes(l.root)

	uassert.Equal(t, 0, l.Compactable())
	uassert.Equal(t, 0, l.Compact())
	uassert.Equal(t, before, countNodes(l.root))
	uassert.Equal(t, 20, l.Size())
	uassert.Equal(t, 20, l.TotalSize())
}

func TestCompactFreesOnlyFullyDeadSubtrees(t *testing.T) {
	tests := []struct {
		name    string
		size    int
		deleted []int
	}{
		{"nothing deleted", 16, nil},
		{"one deleted", 16, []int{9}},
		{"leading run", 32, []int{0, 1, 2, 3, 4, 5, 6, 7}},
		{"trailing run", 32, []int{24, 25, 26, 27, 28, 29, 30, 31}},
		{"every other", 32, []int{1, 3, 5, 7, 9, 11, 13, 15}},
		{"all but one", 16, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}},
		{"all of them", 16, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 14}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := New()
			l.Append(generateSequence(tt.size)...)
			for _, i := range tt.deleted {
				uassert.NoError(t, l.Delete(i))
			}

			// Every surviving element, recorded before the compaction.
			survivors := map[int]any{}
			for i := 0; i < tt.size; i++ {
				if v := l.Get(i); v != nil {
					survivors[i] = v
				}
			}

			predicted := l.Compactable()
			nodesBefore := countNodes(l.root)
			freed := l.Compact()

			// Compactable and Compact must agree, and both must match the tree.
			uassert.Equal(t, predicted, freed)
			uassert.Equal(t, nodesBefore-freed, countNodes(l.root))

			// A second pass has nothing left to do: Compact is idempotent.
			uassert.Equal(t, 0, l.Compactable())
			uassert.Equal(t, 0, l.Compact())

			// Indices are preserved: every survivor is still at its own index,
			// and the sizes are untouched.
			uassert.Equal(t, tt.size, l.TotalSize())
			uassert.Equal(t, len(survivors), l.Size())
			for i, want := range survivors {
				uassert.Equal(t, want, l.Get(i))
			}

			// Appends continue from the same number.
			l.Append("after")
			uassert.Equal(t, "after", l.Get(tt.size))
			uassert.Equal(t, tt.size+1, l.TotalSize())
		})
	}
}

func TestCompactNeverFreesTheRoot(t *testing.T) {
	// Index 0 is the root. Deleting everything must still leave it, or
	// findNode would treat the list as empty and write the next append to
	// index 0.
	l := New()
	l.Append("a", "b", "c")
	uassert.NoError(t, l.Delete(0, 1, 2))
	l.Compact()

	uassert.True(t, l.root != nil)
	uassert.Equal(t, 1, countNodes(l.root))
	uassert.Equal(t, 0, l.Size())
	uassert.Equal(t, 3, l.TotalSize())

	l.Append("d")
	uassert.Equal(t, "d", l.Get(3))
	uassert.Equal(t, nil, l.Get(0))
}

func TestCompactMakesDeletedElementsUnrestorable(t *testing.T) {
	// The documented behaviour change against v0: a soft-deleted element can
	// be restored with Set, but not once its node has been freed and the
	// storage deposit refunded.
	l := New()
	l.Append(generateSequence(8)...)
	uassert.NoError(t, l.Delete(4, 5, 6, 7))

	// Before compaction: restoring works.
	uassert.NoError(t, l.Set(5, "restored"))
	uassert.Equal(t, "restored", l.Get(5))
	uassert.NoError(t, l.Delete(5))

	uassert.True(t, l.Compact() > 0)

	// After compaction: the node is gone, so there is nothing to restore.
	uassert.Error(t, l.Set(5, "restored again"))
	uassert.Equal(t, nil, l.Get(5))
	// And a live element is still perfectly settable.
	uassert.NoError(t, l.Set(1, "still here"))
	uassert.Equal(t, "still here", l.Get(1))
}

func TestCompactLeavesIterationUnchanged(t *testing.T) {
	collect := func(l *List) []Entry {
		var got []Entry
		l.Iterator(0, l.TotalSize()-1, func(i int, v any) bool {
			got = append(got, Entry{Index: i, Value: v})
			return false
		})
		return got
	}

	l := New()
	l.Append(generateSequence(24)...)
	uassert.NoError(t, l.Delete(16, 17, 18, 19, 20, 21, 22, 23))

	before := collect(l)
	l.Compact()
	after := collect(l)

	uassert.Equal(t, len(before), len(after))
	for i := range before {
		uassert.Equal(t, before[i].Index, after[i].Index)
		uassert.Equal(t, before[i].Value, after[i].Value)
	}
}
