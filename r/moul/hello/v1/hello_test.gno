package hello

import (
	"strings"
	"testing"
)

func TestGreetAndCount(cur realm, t *testing.T) {
	if got := Count(); got != 0 {
		t.Fatalf("initial count = %d, want 0", got)
	}
	if got := Greet(cross(cur), "moul"); got != "Hello, moul!" {
		t.Errorf("Greet = %q, want %q", got, "Hello, moul!")
	}
	Greet(cross(cur), "")
	if got := Count(); got != 2 {
		t.Errorf("count = %d, want 2", got)
	}
}

func TestRender(t *testing.T) {
	out := Render("")
	if !strings.Contains(out, "r/moul/hello/v1") {
		t.Errorf("render missing header: %q", out)
	}
}
