package governor

import (
	"testing"

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

func TestIDKey(t *testing.T) {
	// keys are zero-padded so lexical order matches numeric order
	uassert.Equal(t, "000000000001", idKey(1), "id 1")
	uassert.Equal(t, "000000000042", idKey(42), "id 42")
	uassert.True(t, idKey(2) < idKey(10), "2 sorts before 10")
	uassert.True(t, idKey(9) < idKey(100), "9 sorts before 100")
}
