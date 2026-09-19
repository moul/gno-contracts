package governor

import (
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestComputeState(t *testing.T) {
	tests := []struct {
		name string
		p    *Proposal
		h    int64
		want string
	}{
		{
			name: "before deadline is active",
			p:    &Proposal{Deadline: 100, For: 0, Against: 0},
			h:    50,
			want: StateActive,
		},
		{
			name: "at deadline with for>against succeeds",
			p:    &Proposal{Deadline: 100, For: 3, Against: 1},
			h:    100,
			want: StateSucceeded,
		},
		{
			name: "past deadline tie is defeated",
			p:    &Proposal{Deadline: 100, For: 2, Against: 2},
			h:    120,
			want: StateDefeated,
		},
		{
			name: "past deadline against wins is defeated",
			p:    &Proposal{Deadline: 100, For: 1, Against: 5},
			h:    101,
			want: StateDefeated,
		},
		{
			name: "executed overrides everything",
			p:    &Proposal{Deadline: 100, For: 9, Against: 0, Executed: true},
			h:    200,
			want: StateExecuted,
		},
	}
	for _, tt := range tests {
		got := computeState(tt.p, tt.h)
		uassert.Equal(t, tt.want, got, tt.name)
	}
}

func TestBar(t *testing.T) {
	// empty total renders all-empty of exact width
	uassert.Equal(t, "░░░░░░░░░░", bar(0, 0, 10), "zero total")
	// full value fills entirely
	uassert.Equal(t, "▓▓▓▓▓▓▓▓▓▓", bar(10, 10, 10), "full")
	// half value fills half
	uassert.Equal(t, "▓▓▓▓▓░░░░░", bar(5, 10, 10), "half")
	// zero width yields empty string
	uassert.Equal(t, "", bar(1, 2, 0), "zero width")
}

// v0 asserted that its own idKey() padded to width 12. That rule held only
// below the width: idKey(10^12) is 13 characters and sorts before
// idKey(10^12-1), so the proposal list would have rendered out of order from
// that id on. The store key has no width to outgrow.
func TestIDKey(t *testing.T) {
	uassert.True(t, store.ID(2).Key() < store.ID(10).Key(), "2 sorts before 10")
	uassert.True(t, store.ID(9).Key() < store.ID(100).Key(), "9 sorts before 100")
	uassert.True(t, store.ID(999999999999).Key() < store.ID(1000000000000).Key(),
		"and it keeps holding one past v0's width-12 ceiling")
}
