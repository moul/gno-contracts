package ninep

import "testing"

func TestPermString(t *testing.T) {
	tests := []struct {
		name string
		perm Perm
		want string
	}{
		{"dir 0755", DMDIR | 0755, "drwxr-xr-x"},
		{"file 0644", 0644, "-rw-r--r--"},
		{"file 0600", 0600, "-rw-------"},
		{"file 0777", 0777, "-rwxrwxrwx"},
		{"file 0000", 0, "----------"},
		{"append only", DMAPPEND | 0644, "arw-r--r--"},
		{"exclusive", DMEXCL | 0600, "lrw-------"},
		{"dir default", DirPerm, "drwxr-xr-x"},
		{"file default", FilePerm, "-rw-r--r--"},
	}
	for _, tt := range tests {
		if got := tt.perm.String(); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestPermIsDir(t *testing.T) {
	if !(DMDIR | 0755).IsDir() {
		t.Error("DMDIR|0755 should be a directory")
	}
	if Perm(0644).IsDir() {
		t.Error("0644 should not be a directory")
	}
}

func TestQidString(t *testing.T) {
	tests := []struct {
		name string
		qid  Qid
		want string
	}{
		{"root", Qid{Type: QTDIR, Version: 0, Path: 0}, "(0 0 d)"},
		{"file", Qid{Type: QTFILE, Version: 3, Path: 17}, "(11 3 f)"},
		{"big path", Qid{Type: QTFILE, Version: 1, Path: 255}, "(ff 1 f)"},
	}
	for _, tt := range tests {
		if got := tt.qid.String(); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestStatLine(t *testing.T) {
	s := Stat{
		Qid:    Qid{Type: QTFILE, Path: 2, Version: 1},
		Mode:   0644,
		Length: 12,
		Name:   "greeting",
		Uid:    "glenda",
		Gid:    "sys",
	}
	want := "-rw-r--r-- glenda       sys           12 greeting"
	if got := s.Line(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestValidName(t *testing.T) {
	tests := []struct {
		name string
		want bool
	}{
		{"dev", true},
		{"a.b", true},
		{"with space", true},
		{"", false},
		{".", false},
		{"..", false},
		{"a/b", false},
		{"/", false},
	}
	for _, tt := range tests {
		if got := ValidName(tt.name); got != tt.want {
			t.Errorf("ValidName(%q): got %v, want %v", tt.name, got, tt.want)
		}
	}
}

func TestClean(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"", "/"},
		{"/", "/"},
		{"dev", "/dev"},
		{"/dev/", "/dev"},
		{"/dev//height", "/dev/height"},
		{"/dev/./height", "/dev/height"},
		{"/dev/../srv", "/srv"},
		{"/../..", "/"},
		{"/a/b/../../c", "/c"},
	}
	for _, tt := range tests {
		if got := Clean(tt.in); got != tt.want {
			t.Errorf("Clean(%q): got %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestAbs(t *testing.T) {
	tests := []struct {
		cwd  string
		in   string
		want string
	}{
		{"/", "dev", "/dev"},
		{"/usr/glenda", "bin", "/usr/glenda/bin"},
		{"/usr/glenda", "/dev", "/dev"},
		{"/usr/glenda", "..", "/usr"},
		{"/usr/glenda", "", "/usr/glenda"},
		{"", "dev", "/dev"},
	}
	for _, tt := range tests {
		if got := Abs(tt.cwd, tt.in); got != tt.want {
			t.Errorf("Abs(%q, %q): got %q, want %q", tt.cwd, tt.in, got, tt.want)
		}
	}
}

func TestElems(t *testing.T) {
	tests := []struct {
		in   string
		want []string
	}{
		{"/", nil},
		{"", nil},
		{"/dev", []string{"dev"}},
		{"/dev/height", []string{"dev", "height"}},
		{"/a/b/../c", []string{"a", "c"}},
	}
	for _, tt := range tests {
		got := Elems(tt.in)
		if len(got) != len(tt.want) {
			t.Errorf("Elems(%q): got %v, want %v", tt.in, got, tt.want)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("Elems(%q)[%d]: got %q, want %q", tt.in, i, got[i], tt.want[i])
			}
		}
	}
}

func TestBaseDirJoin(t *testing.T) {
	if got := Base("/dev/height"); got != "height" {
		t.Errorf("Base: got %q", got)
	}
	if got := Base("/"); got != "/" {
		t.Errorf("Base of root: got %q", got)
	}
	if got := Dir("/dev/height"); got != "/dev" {
		t.Errorf("Dir: got %q", got)
	}
	if got := Join("/dev", "height"); got != "/dev/height" {
		t.Errorf("Join: got %q", got)
	}
	if got := Join("/", "dev"); got != "/dev" {
		t.Errorf("Join at root: got %q", got)
	}
}

func TestSlice(t *testing.T) {
	const s = "hello world"
	tests := []struct {
		name  string
		off   int64
		count int64
		want  string
	}{
		{"whole", 0, -1, "hello world"},
		{"prefix", 0, 5, "hello"},
		{"middle", 6, 5, "world"},
		{"past end", 99, 5, ""},
		{"count past end", 6, 99, "world"},
		{"negative offset clamps", -4, 5, "hello"},
		{"zero count", 0, 0, ""},
	}
	for _, tt := range tests {
		if got := Slice(s, tt.off, tt.count); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}
