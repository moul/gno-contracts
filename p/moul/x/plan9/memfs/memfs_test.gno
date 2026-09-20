package memfs

import (
	"testing"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

func TestRootStat(t *testing.T) {
	fs := New("glenda", 100)
	s := fs.Root().Stat()
	if s.Name != "/" {
		t.Errorf("root name: got %q", s.Name)
	}
	if !s.IsDir() {
		t.Error("root should be a directory")
	}
	if s.Length != 0 {
		t.Errorf("a directory reports length 0 in 9P, got %d", s.Length)
	}
	if s.Uid != "glenda" || s.Gid != "glenda" {
		t.Errorf("owner: got %q/%q", s.Uid, s.Gid)
	}
	if s.Mtime != 100 {
		t.Errorf("mtime: got %d, want 100", s.Mtime)
	}
}

func TestCreateWalkRead(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()

	f, err := root.Create("greeting", ninep.FilePerm, 2)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	m := f.(ninep.Mutable)
	n, err := m.Write(0, "hello world", 3)
	if err != nil {
		t.Fatalf("write: %v", err)
	}
	if n != 11 {
		t.Errorf("wrote %d bytes, want 11", n)
	}

	got, err := root.Walk("greeting")
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	data, err := ninep.ReadAll(got)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if data != "hello world" {
		t.Errorf("read back %q", data)
	}
	if l := got.Stat().Length; l != 11 {
		t.Errorf("length %d, want 11", l)
	}
}

func TestWalkErrors(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	root.Create("file", ninep.FilePerm, 1)

	if _, err := root.Walk("absent"); err != ninep.ErrNotExist {
		t.Errorf("missing name: got %v, want ErrNotExist", err)
	}
	if _, err := root.Walk("a/b"); err != ninep.ErrBadName {
		t.Errorf("slash in name: got %v, want ErrBadName", err)
	}
	f, _ := root.Walk("file")
	if _, err := f.Walk("x"); err != ninep.ErrNotDir {
		t.Errorf("walk through a file: got %v, want ErrNotDir", err)
	}
	if _, err := f.ReadDir(); err != ninep.ErrNotDir {
		t.Errorf("readdir of a file: got %v, want ErrNotDir", err)
	}
	if _, err := root.Read(0, -1); err != ninep.ErrIsDir {
		t.Errorf("read of a directory: got %v, want ErrIsDir", err)
	}
}

func TestReadDirIsOrdered(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	for _, name := range []string{"zulu", "alpha", "mike", "bravo"} {
		if _, err := root.Create(name, ninep.FilePerm, 1); err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
	}
	ents, err := root.ReadDir()
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	want := []string{"alpha", "bravo", "mike", "zulu"}
	if len(ents) != len(want) {
		t.Fatalf("got %d entries, want %d", len(ents), len(want))
	}
	for i, w := range want {
		if ents[i].Name != w {
			t.Errorf("entry %d: got %q, want %q", i, ents[i].Name, w)
		}
	}
}

func TestCreateDuplicate(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	root.Create("x", ninep.FilePerm, 1)
	if _, err := root.Create("x", ninep.FilePerm, 1); err != ninep.ErrExist {
		t.Errorf("got %v, want ErrExist", err)
	}
	if _, err := root.Create("", ninep.FilePerm, 1); err != ninep.ErrBadName {
		t.Errorf("empty name: got %v, want ErrBadName", err)
	}
	if _, err := root.Create("..", ninep.FilePerm, 1); err != ninep.ErrBadName {
		t.Errorf("dotdot: got %v, want ErrBadName", err)
	}
}

func TestRemove(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	root.Create("file", ninep.FilePerm, 1)
	d, _ := root.Create("dir", ninep.DirPerm, 1)
	d.(ninep.Mutable).Create("inner", ninep.FilePerm, 1)

	if err := root.Remove("absent"); err != ninep.ErrNotExist {
		t.Errorf("remove missing: got %v", err)
	}
	if err := root.Remove("dir"); err != ninep.ErrNotEmpty {
		t.Errorf("remove non-empty dir: got %v, want ErrNotEmpty", err)
	}
	if err := d.(ninep.Mutable).Remove("inner"); err != nil {
		t.Fatalf("remove inner: %v", err)
	}
	if err := root.Remove("dir"); err != nil {
		t.Fatalf("remove emptied dir: %v", err)
	}
	if err := root.Remove("file"); err != nil {
		t.Fatalf("remove file: %v", err)
	}
	ents, _ := root.ReadDir()
	if len(ents) != 0 {
		t.Errorf("root should be empty, has %d entries", len(ents))
	}
}

func TestWriteOffsets(t *testing.T) {
	tests := []struct {
		name  string
		start string
		off   int64
		data  string
		want  string
	}{
		{"append at end", "abc", 3, "def", "abcdef"},
		{"overwrite middle", "abcdef", 2, "XY", "abXYef"},
		{"overwrite past end", "abc", 2, "XYZ", "abXYZ"},
		{"from zero", "abcdef", 0, "ZZ", "ZZcdef"},
		{"gap is nul filled", "ab", 4, "Z", "ab\x00\x00Z"},
		{"negative offset clamps", "abc", -2, "Z", "Zbc"},
	}
	for _, tt := range tests {
		fs := New("glenda", 1)
		root := fs.RootMutable()
		f, _ := root.Create("f", ninep.FilePerm, 1)
		m := f.(ninep.Mutable)
		m.Write(0, tt.start, 1)
		m.Write(tt.off, tt.data, 2)
		got, _ := ninep.ReadAll(f)
		if got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestAppendOnlyIgnoresOffset(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	f, _ := root.Create("log", ninep.DMAPPEND|0644, 1)
	m := f.(ninep.Mutable)
	m.Write(0, "one\n", 1)
	m.Write(0, "two\n", 2) // offset 0, but append-only pins it to the end
	got, _ := ninep.ReadAll(f)
	if got != "one\ntwo\n" {
		t.Errorf("got %q", got)
	}
}

func TestTruncate(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	f, _ := root.Create("f", ninep.FilePerm, 1)
	m := f.(ninep.Mutable)
	m.Write(0, "abcdef", 1)

	m.Truncate(3, 2)
	if got, _ := ninep.ReadAll(f); got != "abc" {
		t.Errorf("shrink: got %q", got)
	}
	m.Truncate(5, 3)
	if got, _ := ninep.ReadAll(f); got != "abc\x00\x00" {
		t.Errorf("grow: got %q", got)
	}
	m.Truncate(0, 4)
	if got, _ := ninep.ReadAll(f); got != "" {
		t.Errorf("zero: got %q", got)
	}
}

func TestQidVersionAndPath(t *testing.T) {
	fs := New("glenda", 1)
	root := fs.RootMutable()
	a, _ := root.Create("a", ninep.FilePerm, 1)
	b, _ := root.Create("b", ninep.FilePerm, 1)

	if a.Stat().Qid.Path == b.Stat().Qid.Path {
		t.Error("two files share a qid path")
	}
	v0 := a.Stat().Qid.Version
	a.(ninep.Mutable).Write(0, "x", 2)
	if a.Stat().Qid.Version != v0+1 {
		t.Errorf("version did not advance on write: %d -> %d", v0, a.Stat().Qid.Version)
	}
	if a.Stat().Mtime != 2 {
		t.Errorf("mtime: got %d, want 2", a.Stat().Mtime)
	}
}

func TestMkdirAllAndWriteFile(t *testing.T) {
	fs := New("glenda", 1)
	if _, err := fs.MkdirAll("/usr/glenda/lib", 1); err != nil {
		t.Fatalf("mkdirall: %v", err)
	}
	// idempotent
	if _, err := fs.MkdirAll("/usr/glenda", 1); err != nil {
		t.Fatalf("mkdirall again: %v", err)
	}
	if err := fs.WriteFile("/usr/glenda/lib/profile", "font=pelm\n", 2); err != nil {
		t.Fatalf("writefile: %v", err)
	}
	f, err := ninep.Walk(fs.Root(), ninep.Elems("/usr/glenda/lib/profile"))
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	if got, _ := ninep.ReadAll(f); got != "font=pelm\n" {
		t.Errorf("got %q", got)
	}
	// rewriting replaces rather than appends
	if err := fs.WriteFile("/usr/glenda/lib/profile", "font=lucida\n", 3); err != nil {
		t.Fatalf("rewrite: %v", err)
	}
	f, _ = ninep.Walk(fs.Root(), ninep.Elems("/usr/glenda/lib/profile"))
	if got, _ := ninep.ReadAll(f); got != "font=lucida\n" {
		t.Errorf("rewrite got %q", got)
	}
}

func TestMkdirAllThroughAFileFails(t *testing.T) {
	fs := New("glenda", 1)
	fs.WriteFile("/etc", "not a directory", 1)
	if _, err := fs.MkdirAll("/etc/passwd", 2); err != ninep.ErrNotDir {
		t.Errorf("got %v, want ErrNotDir", err)
	}
}

func TestWalkDepthLimit(t *testing.T) {
	fs := New("glenda", 1)
	elems := []string{}
	for i := 0; i <= ninep.MaxDepth; i++ {
		elems = append(elems, "x")
	}
	if _, err := ninep.Walk(fs.Root(), elems); err != ninep.ErrTooDeep {
		t.Errorf("got %v, want ErrTooDeep", err)
	}
}
