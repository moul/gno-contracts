package trie

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestInsertAndContains(t *testing.T) {
	cases := []struct {
		name     string
		word     string
		wantOK   bool
		contains bool
	}{
		{"plain word", "car", true, true},
		{"empty rejected", "", false, false},
		{"too long rejected", strings.Repeat("a", MaxWordLen+1), false, false},
		{"exactly max accepted", strings.Repeat("b", MaxWordLen), true, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			tr := New()
			uassert.Equal(t, c.wantOK, tr.Insert(c.word))
			uassert.Equal(t, c.contains, tr.Contains(c.word))
		})
	}
}

func TestInsertIsIdempotent(t *testing.T) {
	tr := New()
	uassert.True(t, tr.Insert("gno"))
	uassert.False(t, tr.Insert("gno"))
	uassert.Equal(t, 1, tr.Len())
}

// A prefix of a stored word is not itself a word until inserted.
func TestPrefixIsNotAWord(t *testing.T) {
	tr := FromWords([]string{"carpet"})
	uassert.False(t, tr.Contains("car"))
	uassert.True(t, tr.HasPrefix("car"))
	uassert.True(t, tr.Contains("carpet"))
}

func TestCompleteIsLexicographic(t *testing.T) {
	// deliberately inserted out of order
	tr := FromWords([]string{"carpet", "car", "cat", "dog", "cart"})
	got := tr.Complete("car", 0)
	want := []string{"car", "carpet", "cart"}
	uassert.Equal(t, strings.Join(want, ","), strings.Join(got, ","))
}

func TestCompleteLimit(t *testing.T) {
	tr := FromWords([]string{"a", "ab", "abc", "abcd"})
	uassert.Equal(t, 2, len(tr.Complete("a", 2)))
	uassert.Equal(t, 4, len(tr.Complete("a", 0)))
	uassert.Equal(t, 4, len(tr.Complete("a", -1)))
}

func TestCompleteUnknownPrefixIsEmptyNotNil(t *testing.T) {
	tr := FromWords([]string{"gno"})
	got := tr.Complete("zzz", 0)
	uassert.Equal(t, 0, len(got))
	// must be safe to range over / join without a nil check
	uassert.Equal(t, "", strings.Join(got, ","))
}

func TestEmptyPrefixListsEverything(t *testing.T) {
	tr := FromWords([]string{"beta", "alpha", "gamma"})
	uassert.Equal(t, "alpha,beta,gamma", strings.Join(tr.Words(), ","))
	uassert.True(t, tr.HasPrefix(""))
	uassert.False(t, New().HasPrefix(""))
}

func TestUnicode(t *testing.T) {
	tr := FromWords([]string{"éclair", "école", "zèbre"})
	uassert.Equal(t, "éclair,école", strings.Join(tr.Complete("é", 0), ","))
	uassert.True(t, tr.Contains("zèbre"))
}

// Children are kept sorted on insert, so output order never depends on
// insertion order — the property that keeps Render deterministic on-chain.
func TestOrderIndependentOfInsertionOrder(t *testing.T) {
	a := FromWords([]string{"delta", "alpha", "charlie", "bravo"})
	b := FromWords([]string{"bravo", "charlie", "alpha", "delta"})
	uassert.Equal(t, strings.Join(a.Words(), ","), strings.Join(b.Words(), ","))
}
