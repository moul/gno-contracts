// Package rc is a small shell over a Plan 9 namespace.
//
// It exists because a namespace you cannot inspect is a namespace you cannot
// trust. Everything here operates on a gno.land/p/moul/x/plan9/ns namespace
// and returns text, so one realm's Render becomes a file browser and one
// transaction becomes a shell command:
//
//	Exec("bind -a /srv/dev /dev; echo hello > /tmp/greeting")
//
// The mode split is the security model. A Shell in ReadOnly mode refuses every
// mutating command, which is what lets a realm expose the shell through
// Render, where mutating anything would be a bug, while the same code backs a
// crossing Exec that may write.
//
// Quoting follows rc: single quotes, with ” inside a quoted string standing
// for one literal quote. Commands are separated by ';' or newlines, and
// quoting is respected when splitting them.
//
// On the first error the run STOPS and returns it. A realm should let that
// error panic, so a half-applied command line reverts with the transaction
// rather than leaving the namespace in a state nobody asked for.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This package is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package rc

import (
	"errors"
	"strconv"
	"strings"

	memfs "gno.land/p/moul/x/plan9/memfs/v0"
	ninep "gno.land/p/moul/x/plan9/ninep/v0"
	ns "gno.land/p/moul/x/plan9/ns/v0"
)

// Mode decides whether mutating commands are allowed.
type Mode uint8

// Shell modes.
const (
	ReadOnly  Mode = 0
	ReadWrite Mode = 1
)

var (
	// ErrReadOnly is returned when a mutating command runs in ReadOnly mode.
	ErrReadOnly = errors.New("read-only shell")
	// ErrUsage reports a malformed command line.
	ErrUsage = errors.New("usage")
	// ErrUnknown reports a command this shell does not have.
	ErrUnknown = errors.New("command not found")
	// ErrQuote reports an unterminated quoted string.
	ErrQuote = errors.New("unterminated '")
)

// MaxCommands bounds one run, so a single call cannot loop the VM.
const MaxCommands = 32

// Shell runs commands against one namespace.
type Shell struct {
	ns   *ns.Ns
	mode Mode
	now  func() int64
}

// New returns a shell over n. now supplies the block height stamped on writes
// and may be nil in ReadOnly mode.
func New(n *ns.Ns, mode Mode, now func() int64) *Shell {
	return &Shell{ns: n, mode: mode, now: now}
}

// Ns returns the namespace the shell operates on.
func (s *Shell) Ns() *ns.Ns { return s.ns }

func (s *Shell) clock() int64 {
	if s.now == nil {
		return 0
	}
	return s.now()
}

func (s *Shell) writable() error {
	if s.mode != ReadWrite {
		return ErrReadOnly
	}
	return nil
}

// Run executes a command line and returns its output. Execution stops at the
// first error.
func (s *Shell) Run(line string) (string, error) {
	cmds, err := splitCommands(line)
	if err != nil {
		return "", err
	}
	if len(cmds) > MaxCommands {
		return "", errors.New("too many commands in one line")
	}
	var out strings.Builder
	for _, c := range cmds {
		toks, err := tokenize(c)
		if err != nil {
			return out.String(), err
		}
		if len(toks) == 0 {
			continue
		}
		text, err := s.run1(toks)
		out.WriteString(text)
		if err != nil {
			return out.String(), errors.New(toks[0] + ": " + err.Error())
		}
	}
	return out.String(), nil
}

func (s *Shell) run1(toks []string) (string, error) {
	cmd, args := toks[0], toks[1:]
	switch cmd {
	case "help":
		return help, nil
	case "pwd":
		return s.ns.Cwd() + "\n", nil
	case "cd":
		return "", s.cd(args)
	case "ns":
		return s.ns.String(), nil
	case "ls":
		return s.ls(args)
	case "cat":
		return s.cat(args)
	case "stat":
		return s.stat(args)
	case "walk":
		return s.walk(args)
	case "bind", "mount":
		return "", s.bind(cmd, args)
	case "unmount", "unbind":
		return "", s.unmount(args)
	case "mkdir":
		return "", s.mkdir(args)
	case "rm":
		return "", s.rm(args)
	case "echo":
		return s.echo(args)
	}
	return "", ErrUnknown
}

const help = `bind [-a|-b|-c] new old   make new visible at old (-b before, -a after, -c creates)
cat file...               print files
cd [dir]                  change directory
echo [-n] word... [>|>> file]
ls [-l] [-u] [path...]    list; -l long, -u collapse union duplicates
mkdir path...             create directories
mount                     synonym for bind
ns                        print the namespace
pwd                       print the working directory
rm path...                remove files and empty directories
stat path...              print the 9P stat of each path
unmount [new] old         undo a binding
walk path                 show how each element of path resolves
`

func (s *Shell) cd(args []string) error {
	if len(args) == 0 {
		return s.ns.Cd("/")
	}
	if len(args) > 1 {
		return ErrUsage
	}
	return s.ns.Cd(args[0])
}

func (s *Shell) ls(args []string) (string, error) {
	long, unique, paths := false, false, []string{}
	for _, a := range args {
		if strings.HasPrefix(a, "-") && len(a) > 1 {
			for _, r := range a[1:] {
				switch r {
				case 'l':
					long = true
				case 'u':
					unique = true
				default:
					return "", ErrUsage
				}
			}
			continue
		}
		paths = append(paths, a)
	}
	if len(paths) == 0 {
		paths = []string{s.ns.Cwd()}
	}
	var out strings.Builder
	for i, p := range paths {
		st, err := s.ns.Stat(p)
		if err != nil {
			return out.String(), err
		}
		if len(paths) > 1 {
			if i > 0 {
				out.WriteString("\n")
			}
			out.WriteString(s.ns.Abs(p) + ":\n")
		}
		if !st.IsDir() {
			out.WriteString(entryLine(st, long))
			continue
		}
		ents, err := s.ns.ReadDir(p, unique)
		if err != nil {
			return out.String(), err
		}
		for _, e := range ents {
			out.WriteString(entryLine(e, long))
		}
	}
	return out.String(), nil
}

func entryLine(st ninep.Stat, long bool) string {
	if long {
		return st.Line() + "\n"
	}
	name := st.Name
	if st.IsDir() && name != "/" {
		name += "/"
	}
	return name + "\n"
}

func (s *Shell) cat(args []string) (string, error) {
	if len(args) == 0 {
		return "", ErrUsage
	}
	var out strings.Builder
	for _, p := range args {
		data, err := s.ns.ReadFile(p)
		if err != nil {
			return out.String(), err
		}
		out.WriteString(data)
	}
	return out.String(), nil
}

func (s *Shell) stat(args []string) (string, error) {
	if len(args) == 0 {
		args = []string{s.ns.Cwd()}
	}
	var out strings.Builder
	for _, p := range args {
		st, err := s.ns.Stat(p)
		if err != nil {
			return out.String(), err
		}
		members, err := s.ns.Resolve(p)
		if err != nil {
			return out.String(), err
		}
		out.WriteString(s.ns.Abs(p) + " " + st.Qid.String() +
			" " + st.Mode.String() +
			" uid=" + st.Uid +
			" length=" + strconv.FormatInt(st.Length, 10) +
			" mtime=" + strconv.FormatInt(st.Mtime, 10) +
			" union=" + strconv.Itoa(len(members)) + "\n")
	}
	return out.String(), nil
}

// walk shows the resolution of each element, which is where a namespace stops
// being magic: the union width column says exactly when a bind took effect.
func (s *Shell) walk(args []string) (string, error) {
	if len(args) != 1 {
		return "", ErrUsage
	}
	abs := s.ns.Abs(args[0])
	var out strings.Builder
	prefix := "/"
	report := func(p string) error {
		st, err := s.ns.Stat(p)
		if err != nil {
			return err
		}
		members, err := s.ns.Resolve(p)
		if err != nil {
			return err
		}
		out.WriteString(pad(p, 24) + " " + st.Qid.String() + " " +
			st.Mode.String() + " union=" + strconv.Itoa(len(members)) + "\n")
		return nil
	}
	if err := report("/"); err != nil {
		return out.String(), err
	}
	for _, e := range ninep.Elems(abs) {
		prefix = ninep.Join(prefix, e)
		if err := report(prefix); err != nil {
			return out.String(), err
		}
	}
	return out.String(), nil
}

func pad(s string, n int) string {
	for len(s) < n {
		s += " "
	}
	return s
}

func (s *Shell) bind(verb string, args []string) error {
	if err := s.writable(); err != nil {
		return err
	}
	flag := ns.MREPL
	rest := []string{}
	for _, a := range args {
		if strings.HasPrefix(a, "-") && len(a) > 1 {
			for _, r := range a[1:] {
				switch r {
				case 'b':
					flag = flag&^0x3 | ns.MBEFORE
				case 'a':
					flag = flag&^0x3 | ns.MAFTER
				case 'c':
					flag |= ns.MCREATE
				default:
					return ErrUsage
				}
			}
			continue
		}
		rest = append(rest, a)
	}
	if len(rest) != 2 {
		return ErrUsage
	}
	return s.ns.BindVerb(verb, rest[0], rest[1], flag)
}

func (s *Shell) unmount(args []string) error {
	if err := s.writable(); err != nil {
		return err
	}
	switch len(args) {
	case 1:
		return s.ns.Unmount("", args[0])
	case 2:
		return s.ns.Unmount(args[0], args[1])
	}
	return ErrUsage
}

func (s *Shell) mkdir(args []string) error {
	if err := s.writable(); err != nil {
		return err
	}
	if len(args) == 0 {
		return ErrUsage
	}
	for _, p := range args {
		abs := s.ns.Abs(p)
		target, err := s.ns.CreateTarget(ninep.Dir(abs))
		if err != nil {
			return err
		}
		if _, err := target.Create(ninep.Base(abs), ninep.DirPerm, s.clock()); err != nil {
			return err
		}
	}
	return nil
}

func (s *Shell) rm(args []string) error {
	if err := s.writable(); err != nil {
		return err
	}
	if len(args) == 0 {
		return ErrUsage
	}
	for _, p := range args {
		abs := s.ns.Abs(p)
		name := ninep.Base(abs)
		members, err := s.ns.Resolve(ninep.Dir(abs))
		if err != nil {
			return err
		}
		found, removed := false, false
		for _, m := range members {
			if _, err := m.Walk(name); err != nil {
				continue
			}
			found = true
			mu, ok := m.(ninep.Mutable)
			if !ok {
				continue // a read-only server: try the next union member
			}
			if err := mu.Remove(name); err != nil {
				return err
			}
			removed = true
			break
		}
		switch {
		case removed:
		case found:
			return ninep.ErrReadOnly
		default:
			return ninep.ErrNotExist
		}
	}
	return nil
}

func (s *Shell) echo(args []string) (string, error) {
	newline := true
	words := []string{}
	redirect, appendTo, dest := false, false, ""
	i := 0
	for i < len(args) {
		a := args[i]
		switch {
		case a == "-n" && len(words) == 0 && !redirect:
			newline = false
		case a == ">" || a == ">>":
			if i+1 >= len(args) {
				return "", ErrUsage
			}
			redirect, appendTo, dest = true, a == ">>", args[i+1]
			i++
		default:
			words = append(words, a)
		}
		i++
	}
	text := strings.Join(words, " ")
	if newline {
		text += "\n"
	}
	if !redirect {
		return text, nil
	}
	if err := s.writable(); err != nil {
		return "", err
	}
	return "", s.writeTo(dest, text, appendTo)
}

// writeTo creates or opens dest and writes text, honouring the namespace's
// MCREATE rules when the file has to be created.
func (s *Shell) writeTo(dest, text string, appendTo bool) error {
	abs := s.ns.Abs(dest)
	f, err := s.ns.Open(abs)
	if err == ninep.ErrNotExist {
		target, terr := s.ns.CreateTarget(ninep.Dir(abs))
		if terr != nil {
			return terr
		}
		created, cerr := target.Create(ninep.Base(abs), ninep.FilePerm, s.clock())
		if cerr != nil {
			return cerr
		}
		f = created
	} else if err != nil {
		return err
	}
	mu, ok := f.(ninep.Mutable)
	if !ok {
		return ninep.ErrReadOnly
	}
	off := int64(0)
	if appendTo {
		off = mu.Stat().Length
	} else if err := mu.Truncate(0, s.clock()); err != nil {
		return err
	}
	_, err = mu.Write(off, text, s.clock())
	return err
}

// splitCommands splits on ';' and newlines, respecting rc quoting.
func splitCommands(line string) ([]string, error) {
	out := []string{}
	var b strings.Builder
	quoted := false
	for i := 0; i < len(line); i++ {
		c := line[i]
		if c == '\'' {
			quoted = !quoted
		}
		if !quoted && (c == ';' || c == '\n') {
			out = append(out, b.String())
			b.Reset()
			continue
		}
		b.WriteByte(c)
	}
	if quoted {
		return nil, ErrQuote
	}
	out = append(out, b.String())
	return out, nil
}

// tokenize splits one command into words using rc's quoting rules.
func tokenize(s string) ([]string, error) {
	toks := []string{}
	i := 0
	for i < len(s) {
		for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
			i++
		}
		if i >= len(s) {
			break
		}
		var b strings.Builder
		quoted := false
		for i < len(s) {
			c := s[i]
			if c == '\'' {
				if quoted && i+1 < len(s) && s[i+1] == '\'' {
					b.WriteByte('\'')
					i += 2
					continue
				}
				quoted = !quoted
				i++
				continue
			}
			if !quoted && (c == ' ' || c == '\t') {
				break
			}
			b.WriteByte(c)
			i++
		}
		if quoted {
			return nil, ErrQuote
		}
		toks = append(toks, b.String())
	}
	return toks, nil
}

// NewMemShell is the convenience a realm or a test wants: a fresh ram root,
// a namespace over it, and a shell. It exists here rather than in ns so that
// ns keeps no dependency on a particular file server.
func NewMemShell(uid string, mode Mode, now func() int64) (*Shell, *memfs.FS) {
	h := int64(0)
	if now != nil {
		h = now()
	}
	fs := memfs.New(uid, h)
	return New(ns.New(fs.Root()), mode, now), fs
}
