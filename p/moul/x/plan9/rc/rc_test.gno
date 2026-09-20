package rc

import (
	"strings"
	"testing"

	memfs "gno.land/p/moul/x/plan9/memfs/v0"
	ninep "gno.land/p/moul/x/plan9/ninep/v0"
	ns "gno.land/p/moul/x/plan9/ns/v0"
	synfs "gno.land/p/moul/x/plan9/synfs/v0"
)

func clock(h int64) func() int64 { return func() int64 { return h } }

func shell(t *testing.T, files ...string) (*Shell, *memfs.FS) {
	t.Helper()
	sh, fs := NewMemShell("glenda", ReadWrite, clock(100))
	for _, f := range files {
		if err := fs.WriteFile(f, "contents of "+f+"\n", 100); err != nil {
			t.Fatalf("seed %s: %v", f, err)
		}
	}
	return sh, fs
}

func run(t *testing.T, sh *Shell, line string) string {
	t.Helper()
	out, err := sh.Run(line)
	if err != nil {
		t.Fatalf("%s: %v", line, err)
	}
	return out
}

func TestTokenize(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want []string
	}{
		{"plain", "ls -l /dev", []string{"ls", "-l", "/dev"}},
		{"extra spaces", "  ls   /dev  ", []string{"ls", "/dev"}},
		{"quoted", "echo 'hello world'", []string{"echo", "hello world"}},
		{"quote inside quote", "echo 'it''s'", []string{"echo", "it's"}},
		{"empty quoted word", "echo ''", []string{"echo", ""}},
		{"adjacent", "echo a'b c'd", []string{"echo", "ab cd"}},
		{"empty line", "", []string{}},
	}
	for _, tt := range tests {
		got, err := tokenize(tt.in)
		if err != nil {
			t.Errorf("%s: %v", tt.name, err)
			continue
		}
		if len(got) != len(tt.want) {
			t.Errorf("%s: got %v, want %v", tt.name, got, tt.want)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("%s: token %d got %q, want %q", tt.name, i, got[i], tt.want[i])
			}
		}
	}
	if _, err := tokenize("echo 'unterminated"); err != ErrQuote {
		t.Errorf("unterminated quote: got %v", err)
	}
}

func TestSplitCommands(t *testing.T) {
	got, err := splitCommands("pwd; ls /\necho 'a;b'")
	if err != nil {
		t.Fatalf("%v", err)
	}
	want := []string{"pwd", " ls /", "echo 'a;b'"}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("%d: got %q, want %q", i, got[i], want[i])
		}
	}
}

func TestPwdAndCd(t *testing.T) {
	sh, _ := shell(t, "/usr/glenda/lib/profile")
	if got := run(t, sh, "pwd"); got != "/\n" {
		t.Errorf("pwd: %q", got)
	}
	run(t, sh, "cd /usr/glenda")
	if got := run(t, sh, "pwd"); got != "/usr/glenda\n" {
		t.Errorf("pwd after cd: %q", got)
	}
	if got := run(t, sh, "cat lib/profile"); got != "contents of /usr/glenda/lib/profile\n" {
		t.Errorf("relative cat: %q", got)
	}
	run(t, sh, "cd")
	if got := run(t, sh, "pwd"); got != "/\n" {
		t.Errorf("bare cd should go to the root: %q", got)
	}
}

func TestLs(t *testing.T) {
	sh, _ := shell(t, "/bin/ls", "/bin/rc", "/tmp/x")
	if got := run(t, sh, "ls /"); got != "bin/\ntmp/\n" {
		t.Errorf("ls /: %q", got)
	}
	if got := run(t, sh, "ls /bin"); got != "ls\nrc\n" {
		t.Errorf("ls /bin: %q", got)
	}
	long := run(t, sh, "ls -l /bin")
	if !strings.Contains(long, "-rw-r--r-- glenda") {
		t.Errorf("ls -l: %q", long)
	}
	if got := run(t, sh, "ls /bin/ls"); got != "ls\n" {
		t.Errorf("ls of a file: %q", got)
	}
	if _, err := sh.Run("ls -Z"); err == nil {
		t.Error("an unknown flag should fail")
	}
}

func TestLsUnionAndUnique(t *testing.T) {
	sh, fs := shell(t)
	fs.WriteFile("/bin/ls", "system\n", 100)
	fs.WriteFile("/usr/glenda/bin/ls", "mine\n", 100)
	run(t, sh, "bind -b /usr/glenda/bin /bin")

	if got := run(t, sh, "ls /bin"); got != "ls\nls\n" {
		t.Errorf("a union lists both, as Plan 9 does: %q", got)
	}
	if got := run(t, sh, "ls -u /bin"); got != "ls\n" {
		t.Errorf("ls -u: %q", got)
	}
	if got := run(t, sh, "cat /bin/ls"); got != "mine\n" {
		t.Errorf("the member bound before wins the walk: %q", got)
	}
}

func TestCatErrors(t *testing.T) {
	sh, _ := shell(t, "/bin/ls")
	if _, err := sh.Run("cat /bin"); err == nil {
		t.Error("cat of a directory should fail")
	}
	if _, err := sh.Run("cat /absent"); err == nil {
		t.Error("cat of a missing file should fail")
	}
	if _, err := sh.Run("cat"); err == nil {
		t.Error("cat with no argument should fail")
	}
}

func TestEchoAndRedirect(t *testing.T) {
	sh, _ := shell(t)
	if got := run(t, sh, "echo hello world"); got != "hello world\n" {
		t.Errorf("echo: %q", got)
	}
	if got := run(t, sh, "echo -n hello"); got != "hello" {
		t.Errorf("echo -n: %q", got)
	}
	run(t, sh, "echo hello > /greeting")
	if got := run(t, sh, "cat /greeting"); got != "hello\n" {
		t.Errorf("after redirect: %q", got)
	}
	run(t, sh, "echo again >> /greeting")
	if got := run(t, sh, "cat /greeting"); got != "hello\nagain\n" {
		t.Errorf("after append: %q", got)
	}
	run(t, sh, "echo replaced > /greeting")
	if got := run(t, sh, "cat /greeting"); got != "replaced\n" {
		t.Errorf("a plain redirect truncates: %q", got)
	}
	if _, err := sh.Run("echo hi >"); err == nil {
		t.Error("a redirect with no target should fail")
	}
}

func TestMkdirAndRm(t *testing.T) {
	sh, _ := shell(t)
	run(t, sh, "mkdir /tmp")
	run(t, sh, "echo x > /tmp/f")
	if got := run(t, sh, "ls /tmp"); got != "f\n" {
		t.Errorf("ls /tmp: %q", got)
	}
	if _, err := sh.Run("rm /tmp"); err == nil || err.Error() != "rm: "+ninep.ErrNotEmpty.Error() {
		t.Errorf("rm of a non-empty directory: got %v", err)
	}
	run(t, sh, "rm /tmp/f")
	run(t, sh, "rm /tmp")
	if got := run(t, sh, "ls /"); got != "" {
		t.Errorf("root should be empty: %q", got)
	}
	if _, err := sh.Run("rm /absent"); err == nil {
		t.Error("rm of a missing file should fail")
	}
}

func TestBindAndNs(t *testing.T) {
	sh, _ := shell(t, "/bin/ls", "/usr/glenda/bin/rc")
	run(t, sh, "bind -a /usr/glenda/bin /bin")
	if got := run(t, sh, "ls /bin"); got != "ls\nrc\n" {
		t.Errorf("ls after bind: %q", got)
	}
	want := "bind -a /usr/glenda/bin /bin\ncd /\n"
	if got := run(t, sh, "ns"); got != want {
		t.Errorf("ns:\ngot  %q\nwant %q", got, want)
	}
	run(t, sh, "unmount /usr/glenda/bin /bin")
	if got := run(t, sh, "ls /bin"); got != "ls\n" {
		t.Errorf("after unmount: %q", got)
	}
	if got := run(t, sh, "ns"); got != "cd /\n" {
		t.Errorf("ns after unmount: %q", got)
	}
}

func TestMountIsASynonym(t *testing.T) {
	sh, _ := shell(t, "/bin/ls", "/srv/dev/height")
	run(t, sh, "mkdir /dev")
	run(t, sh, "mount /srv/dev /dev")
	if got := run(t, sh, "ls /dev"); got != "height\n" {
		t.Errorf("ls /dev: %q", got)
	}
	if !strings.HasPrefix(run(t, sh, "ns"), "mount /srv/dev /dev\n") {
		t.Errorf("ns should record the verb used: %q", run(t, sh, "ns"))
	}
}

func TestCreateInAUnionNeedsTheFlag(t *testing.T) {
	sh, _ := shell(t, "/bin/ls", "/usr/glenda/bin/rc")
	run(t, sh, "bind -a /usr/glenda/bin /bin")
	if _, err := sh.Run("echo x > /bin/new"); err == nil {
		t.Error("creating in a union with no -c should be refused")
	}
	run(t, sh, "bind -ac /usr/glenda/bin /bin")
	run(t, sh, "echo x > /bin/new")
	if got := run(t, sh, "cat /usr/glenda/bin/new"); got != "x\n" {
		t.Errorf("the create should land in the -c member: %q", got)
	}
}

func TestReadOnlyModeRefusesWrites(t *testing.T) {
	sh, fs := NewMemShell("glenda", ReadOnly, clock(1))
	fs.WriteFile("/bin/ls", "x\n", 1)

	// Reads still work.
	if got := run(t, sh, "ls /bin"); got != "ls\n" {
		t.Errorf("ls: %q", got)
	}
	if got := run(t, sh, "cat /bin/ls"); got != "x\n" {
		t.Errorf("cat: %q", got)
	}
	if got := run(t, sh, "echo hi"); got != "hi\n" {
		t.Errorf("echo without a redirect is not a write: %q", got)
	}
	for _, line := range []string{
		"mkdir /tmp",
		"rm /bin/ls",
		"bind /bin /bin",
		"unmount /bin",
		"echo hi > /f",
	} {
		_, err := sh.Run(line)
		if err == nil {
			t.Errorf("%q should be refused in ReadOnly mode", line)
			continue
		}
		if !strings.Contains(err.Error(), ErrReadOnly.Error()) {
			t.Errorf("%q: got %v, want a read-only error", line, err)
		}
	}
}

func TestStopsAtTheFirstError(t *testing.T) {
	sh, _ := shell(t)
	out, err := sh.Run("echo one; cat /absent; echo three")
	if err == nil {
		t.Fatal("expected an error")
	}
	if out != "one\n" {
		t.Errorf("output should stop at the failure: %q", out)
	}
	if !strings.HasPrefix(err.Error(), "cat: ") {
		t.Errorf("the error should name the command: %v", err)
	}
}

func TestUnknownCommand(t *testing.T) {
	sh, _ := shell(t)
	if _, err := sh.Run("nosuchthing"); err == nil {
		t.Error("expected an error")
	}
}

func TestStatAndWalkShowTheUnion(t *testing.T) {
	sh, fs := shell(t)
	fs.WriteFile("/bin/ls", "a\n", 100)
	fs.WriteFile("/usr/glenda/bin/rc", "b\n", 100)
	run(t, sh, "bind -a /usr/glenda/bin /bin")

	st := run(t, sh, "stat /bin")
	if !strings.Contains(st, "union=2") {
		t.Errorf("stat should report the union width: %q", st)
	}
	w := run(t, sh, "walk /bin/rc")
	lines := strings.Split(strings.TrimSpace(w), "\n")
	if len(lines) != 3 {
		t.Fatalf("walk should report /, /bin and /bin/rc: %q", w)
	}
	if !strings.Contains(lines[1], "union=2") {
		t.Errorf("the union should appear at /bin: %q", lines[1])
	}
	if !strings.Contains(lines[2], "union=1") {
		t.Errorf("a union is top level only, /bin/rc is not one: %q", lines[2])
	}
}

func TestReadOnlyServerMountedInAWritableNamespace(t *testing.T) {
	// This is the cross-realm shape: a synthetic, read-only tree grafted into
	// a namespace whose root is writable. Reads work; writes are refused
	// where the server is read-only and still allowed elsewhere.
	sh, fs := shell(t)
	fs.MkdirAll("/dev", 100)
	tr := synfs.New("dev", "sys", clock(100))
	tr.Root().Add("height", func() string { return "100" })
	if err := sh.Ns().Mount(tr.Root(), "#dev", "/dev", ns.MREPL); err != nil {
		t.Fatalf("mount: %v", err)
	}

	if got := run(t, sh, "cat /dev/height"); got != "100" {
		t.Errorf("read through the mount: %q", got)
	}
	if got := run(t, sh, "ls /dev"); got != "height\n" {
		t.Errorf("ls /dev: %q", got)
	}
	if _, err := sh.Run("echo x > /dev/height"); err == nil {
		t.Error("writing to a read-only server should be refused")
	}
	if _, err := sh.Run("rm /dev/height"); err == nil || err.Error() != "rm: "+ninep.ErrReadOnly.Error() {
		t.Errorf("rm on a read-only server: got %v", err)
	}
	// The rest of the namespace is unaffected.
	run(t, sh, "echo fine > /ok")
	if got := run(t, sh, "cat /ok"); got != "fine\n" {
		t.Errorf("got %q", got)
	}
}

func TestHelpListsEveryCommand(t *testing.T) {
	sh, _ := shell(t)
	out := run(t, sh, "help")
	for _, cmd := range []string{"bind", "cat", "cd", "echo", "ls", "mkdir", "mount", "ns", "pwd", "rm", "stat", "unmount", "walk"} {
		if !strings.Contains(out, cmd) {
			t.Errorf("help does not mention %q", cmd)
		}
	}
}
