package greet

import "testing"

func TestGreet(t *testing.T) {
	cases := map[string]string{
		"":      "Hello, world!",
		"  ":    "Hello, world!",
		"moul":  "Hello, moul!",
		" gno ": "Hello, gno!",
	}
	for in, want := range cases {
		if got := Greet(in); got != want {
			t.Errorf("Greet(%q) = %q, want %q", in, got, want)
		}
	}
}
