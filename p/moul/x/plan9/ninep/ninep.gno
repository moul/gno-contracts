// Package ninep is a Plan 9 shaped file abstraction for gno.
//
// It implements the SEMANTICS of 9P2000, not its wire format: there is no
// socket on a chain, the VM call is the transport. What it keeps is the part
// that made 9P useful, namely that every resource answers the same four
// questions (stat, walk, read, readdir), so a client written today can browse
// a file server deployed tomorrow.
//
// One interface, not two. 9P reads a directory with the same Tread it uses for
// a file, so splitting File from Dir would be less faithful, and a single
// interface means no type assertion across a realm boundary.
//
// Deliberate divergences from 9P2000, all of them forced:
//
//   - Data is a string, not []byte. Every consumer on this chain is text and
//     Render returns a string.
//   - Mtime is a block height, not a wall clock. It is the only clock that
//     every validating node agrees on.
//   - There is no open/clunk pair. Without a session there are no fids, so
//     Walk returns the file itself and nothing has to be released.
//   - File is READ-ONLY. A crossing method would mint the caller's realm frame
//     for the callee, which is a confused-deputy hazard (compare r/gov/dao's
//     Executor, and p/nt/grc20's deliberate refusal to make Teller crossing).
//     Mutation lives in Mutable, which is only safe on a tree your own realm
//     owns.
//
// See gno.land/p/moul/x/plan9/ns for the namespace that binds these trees
// together, and gno.land/p/moul/x/plan9/memfs for the reference server.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This package is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package ninep

import (
	"errors"
	"path"
	"strconv"
	"strings"
)

// Qid type bits, as in 9P2000.
const (
	QTFILE   uint8 = 0x00 // a plain file
	QTTMP    uint8 = 0x04 // not archived
	QTAUTH   uint8 = 0x08 // authentication file
	QTMOUNT  uint8 = 0x10 // mounted channel
	QTEXCL   uint8 = 0x20 // exclusive use
	QTAPPEND uint8 = 0x40 // append only
	QTDIR    uint8 = 0x80 // a directory
)

// Perm holds the 9P mode word: the low nine bits are rwx for owner, group and
// other, the high bits are the DM* kind flags.
type Perm uint32

// Mode bits, as in 9P2000.
const (
	DMTMP    Perm = 0x04000000
	DMAUTH   Perm = 0x08000000
	DMMOUNT  Perm = 0x10000000
	DMEXCL   Perm = 0x20000000
	DMAPPEND Perm = 0x40000000
	DMDIR    Perm = 0x80000000

	PermMask Perm = 0777 // the rwxrwxrwx bits

	// Conventional defaults, matching what Plan 9's ramfs hands out.
	DirPerm  Perm = DMDIR | 0755
	FilePerm Perm = 0644
)

// IsDir reports whether the mode marks a directory.
func (p Perm) IsDir() bool { return p&DMDIR != 0 }

// String renders the mode the way ls -l does: a kind letter then nine rwx
// bits. The kind letter is 'd' for a directory, 'a' for append-only, 'l' for
// exclusive-use, '-' otherwise.
func (p Perm) String() string {
	var b strings.Builder
	switch {
	case p&DMDIR != 0:
		b.WriteByte('d')
	case p&DMAPPEND != 0:
		b.WriteByte('a')
	case p&DMEXCL != 0:
		b.WriteByte('l')
	default:
		b.WriteByte('-')
	}
	const rwx = "rwxrwxrwx"
	for i := 0; i < 9; i++ {
		if p&(1<<uint(8-i)) != 0 {
			b.WriteByte(rwx[i])
		} else {
			b.WriteByte('-')
		}
	}
	return b.String()
}

// Qid is the server's unique handle for a file. Path identifies the file
// within one server for its whole lifetime; Version increments on every write,
// so a client can tell "same file, changed" from "different file" without
// reading either.
type Qid struct {
	Type    uint8
	Version uint32
	Path    uint64
}

// IsDir reports whether the qid marks a directory.
func (q Qid) IsDir() bool { return q.Type&QTDIR != 0 }

// String renders the qid as Plan 9 does, "(path version type)", with the path
// in hex.
func (q Qid) String() string {
	kind := "f"
	if q.IsDir() {
		kind = "d"
	}
	return "(" + strconv.FormatUint(q.Path, 16) + " " +
		strconv.FormatUint(uint64(q.Version), 10) + " " + kind + ")"
}

// Stat is 9P's directory entry, minus the fields that only mean something on a
// wire (type, dev) or on a host clock (atime).
type Stat struct {
	Qid    Qid
	Mode   Perm
	Mtime  int64 // block height of the last write
	Length int64 // in bytes; zero for a directory, as in 9P
	Name   string
	Uid    string // owner; a bech32 address, or a well-known name
	Gid    string // group
	Muid   string // last writer
}

// IsDir reports whether the entry is a directory.
func (s Stat) IsDir() bool { return s.Mode.IsDir() }

// Line renders the entry the way ls -l does.
func (s Stat) Line() string {
	return s.Mode.String() + " " + pad(s.Uid, 12) + " " + pad(s.Gid, 8) + " " +
		lpad(strconv.FormatInt(s.Length, 10), 7) + " " + s.Name
}

// pad right-pads to n runes. ufmt has no width flags in gno, so padding is by
// hand everywhere in this suite.
func pad(s string, n int) string {
	for len(s) < n {
		s += " "
	}
	return s
}

func lpad(s string, n int) string {
	for len(s) < n {
		s = " " + s
	}
	return s
}

// File is a 9P file server's whole read surface. Every method must be free of
// side effects: a File is routinely reached across a realm boundary, where the
// running frame belongs to the CALLER, so mutating anything here would be both
// a VM error and a confused deputy.
type File interface {
	// Stat returns the entry for this file.
	Stat() Stat
	// Walk resolves exactly one path element. It returns ErrNotDir on a
	// plain file and ErrNotExist when the name is absent. It never sees
	// "." or "..": both are removed lexically before resolution starts.
	Walk(name string) (File, error)
	// Read returns at most count bytes starting at off. A negative count
	// means "to the end". It returns ErrIsDir on a directory.
	Read(off, count int64) (string, error)
	// ReadDir returns the directory's entries in a deterministic order. It
	// returns ErrNotDir on a plain file.
	ReadDir() ([]Stat, error)
}

// Mutable is the write half, kept out of File on purpose.
//
// It is NOT safe across a realm boundary: a non-crossing method runs in the
// caller's frame, so a foreign realm calling these would be trying to mutate
// objects it does not own. Only call Mutable on a tree your own realm created.
// The caller supplies now (a block height) rather than the tree reading the
// chain itself, so the same code is testable off chain.
type Mutable interface {
	File
	Create(name string, perm Perm, now int64) (File, error)
	Remove(name string) error
	Write(off int64, data string, now int64) (int64, error)
	Truncate(size int64, now int64) error
}

// Plan 9 error strings, kept lowercase and verbatim where they exist.
var (
	ErrNotExist = errors.New("file does not exist")
	ErrNotDir   = errors.New("not a directory")
	ErrIsDir    = errors.New("is a directory")
	ErrExist    = errors.New("file already exists")
	ErrPerm     = errors.New("permission denied")
	ErrNoCreate = errors.New("create prohibited")
	ErrReadOnly = errors.New("read-only file server")
	ErrBadName  = errors.New("bad character in file name")
	ErrNotEmpty = errors.New("directory not empty")
	ErrTooDeep  = errors.New("path too deep")
)

// MaxDepth bounds a walk. Resolution costs one cross-realm call per element
// per union member, so depth is capped rather than trusted.
const MaxDepth = 32

// ValidName reports whether name is usable as a single path element. Plan 9
// rejects the empty name, "." and "..", and any name containing a slash.
func ValidName(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	return !strings.Contains(name, "/")
}

// Clean returns p as a cleaned absolute path. "." and ".." are resolved
// lexically, before any server sees them, which is what makes ".." undo the
// name you typed rather than the directory you landed in (see "Lexical File
// Names in Plan 9").
func Clean(p string) string {
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	return path.Clean(p)
}

// Abs resolves p against cwd, then cleans it.
func Abs(cwd, p string) string {
	if p == "" {
		return Clean(cwd)
	}
	if strings.HasPrefix(p, "/") {
		return Clean(p)
	}
	if cwd == "" {
		cwd = "/"
	}
	return Clean(cwd + "/" + p)
}

// Elems splits a cleaned absolute path into its elements. The root yields nil.
func Elems(p string) []string {
	p = Clean(p)
	if p == "/" {
		return nil
	}
	return strings.Split(p[1:], "/")
}

// Base returns the last element of p, or "/" for the root.
func Base(p string) string { return path.Base(Clean(p)) }

// Dir returns p's parent.
func Dir(p string) string { return path.Dir(Clean(p)) }

// Join appends name to dir.
func Join(dir, name string) string { return Clean(dir + "/" + name) }

// Walk resolves elems from f, one element at a time. It is the plain,
// namespace-free walk: no binds, no unions. Use ns.Ns for those.
func Walk(f File, elems []string) (File, error) {
	if len(elems) > MaxDepth {
		return nil, ErrTooDeep
	}
	for _, e := range elems {
		next, err := f.Walk(e)
		if err != nil {
			return nil, err
		}
		f = next
	}
	return f, nil
}

// ReadAll reads a whole file.
func ReadAll(f File) (string, error) { return f.Read(0, -1) }

// Slice applies 9P's read window to s: at most count bytes from off, with a
// negative count meaning "to the end". An offset past the end reads empty,
// which is what makes a read loop terminate rather than fail.
func Slice(s string, off, count int64) string {
	if off < 0 {
		off = 0
	}
	n := int64(len(s))
	if off >= n {
		return ""
	}
	end := n
	if count >= 0 && off+count < n {
		end = off + count
	}
	return s[off:end]
}
