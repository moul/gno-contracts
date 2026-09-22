package synfs

import (
	"strconv"
	"strings"
	"testing"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

func fixedClock(h int64) func() int64 { return func() int64 { return h } }

func TestTreeShape(t *testing.T) {
	tr := New("dev", "sys", fixedClock(42))
	tr.Root().
		Add("sysname", func() string { return "gnoland-1" }).
		Add("height", func() string { return "42" })

	st := tr.Root().Stat()
	if st.Name != "dev" {
		t.Errorf("root name %q", st.Name)
	}
	if !st.IsDir() {
		t.Error("root should be a directory")
	}
	if st.Mtime != 42 {
		t.Errorf("mtime %d, want 42", st.Mtime)
	}
	if st.Mode.String() != "dr-xr-xr-x" {
		t.Errorf("mode %q, want dr-xr-xr-x", st.Mode.String())
	}
}

func TestReadComputed(t *testing.T) {
	height := int64(100)
	tr := New("dev", "sys", func() int64 { return height })
	tr.Root().Add("height", func() string { return strconv.FormatInt(height, 10) })

	f, err := tr.Root().Walk("height")
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	got, _ := ninep.ReadAll(f)
	if got != "100" {
		t.Errorf("got %q", got)
	}
	// The generator runs on every read, so the file follows the chain.
	height = 101
	got, _ = ninep.ReadAll(f)
	if got != "101" {
		t.Errorf("after the block advanced: got %q", got)
	}
	if v := f.Stat().Qid.Version; v != 0 {
		t.Errorf("a synthetic file pins version 0, got %d", v)
	}
}

func TestReadWindow(t *testing.T) {
	tr := New("dev", "sys", nil)
	tr.Root().Add("msg", func() string { return "hello world" })
	f, _ := tr.Root().Walk("msg")

	tests := []struct {
		off, count int64
		want       string
	}{
		{0, -1, "hello world"},
		{0, 5, "hello"},
		{6, 5, "world"},
		{99, 5, ""},
	}
	for _, tt := range tests {
		got, err := f.Read(tt.off, tt.count)
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		if got != tt.want {
			t.Errorf("Read(%d,%d): got %q, want %q", tt.off, tt.count, got, tt.want)
		}
	}
}

func TestAddRangeEndlessFile(t *testing.T) {
	// /dev/zero has no end: it must serve the window rather than a value.
	tr := New("dev", "sys", nil)
	tr.Root().AddRange("zero", 0444, func(off, count int64) (string, error) {
		if count < 0 {
			count = 0
		}
		return strings.Repeat("0", int(count)), nil
	})
	f, _ := tr.Root().Walk("zero")
	got, _ := f.Read(0, 4)
	if got != "0000" {
		t.Errorf("got %q", got)
	}
	got, _ = f.Read(0, -1)
	if got != "" {
		t.Errorf("an unbounded read of an endless file must not hang or grow: got %q", got)
	}
}

func TestReadDirIsOrdered(t *testing.T) {
	tr := New("dev", "sys", fixedClock(1))
	tr.Root().
		Add("zero", func() string { return "" }).
		Add("null", func() string { return "" }).
		Add("time", func() string { return "" })

	ents, err := tr.Root().ReadDir()
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	want := []string{"null", "time", "zero"}
	if len(ents) != len(want) {
		t.Fatalf("got %d entries", len(ents))
	}
	for i, w := range want {
		if ents[i].Name != w {
			t.Errorf("entry %d: got %q, want %q", i, ents[i].Name, w)
		}
	}
	if got := tr.Root().Names(); len(got) != 3 || got[0] != "null" {
		t.Errorf("Names: %v", got)
	}
}

func TestSubdirectories(t *testing.T) {
	tr := New("proc", "sys", fixedClock(7))
	sub := tr.NewDir("1")
	sub.Add("status", func() string { return "running" })
	tr.Root().AddDir(sub)

	f, err := ninep.Walk(tr.Root(), ninep.Elems("/1/status"))
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	got, _ := ninep.ReadAll(f)
	if got != "running" {
		t.Errorf("got %q", got)
	}
}

func TestErrors(t *testing.T) {
	tr := New("dev", "sys", nil)
	tr.Root().Add("null", func() string { return "" })

	if _, err := tr.Root().Read(0, -1); err != ninep.ErrIsDir {
		t.Errorf("read a directory: got %v", err)
	}
	if _, err := tr.Root().Walk("absent"); err != ninep.ErrNotExist {
		t.Errorf("walk missing: got %v", err)
	}
	if _, err := tr.Root().Walk("a/b"); err != ninep.ErrBadName {
		t.Errorf("walk bad name: got %v", err)
	}
	f, _ := tr.Root().Walk("null")
	if _, err := f.Walk("x"); err != ninep.ErrNotDir {
		t.Errorf("walk through a file: got %v", err)
	}
	if _, err := f.ReadDir(); err != ninep.ErrNotDir {
		t.Errorf("readdir a file: got %v", err)
	}
}

func TestSyntheticTreeIsReadOnly(t *testing.T) {
	// The whole point: a synthetic tree implements File and NOT Mutable, so
	// it is safe to hand to a namespace owned by somebody else.
	tr := New("dev", "sys", nil)
	var f ninep.File = tr.Root()
	if _, ok := f.(ninep.Mutable); ok {
		t.Error("a synthetic tree must not be Mutable")
	}
}
