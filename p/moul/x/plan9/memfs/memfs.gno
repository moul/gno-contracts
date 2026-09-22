// Package memfs is a RAM file server: Plan 9's ramfs, in a realm's heap.
//
// It is the reference implementation of gno.land/p/moul/x/plan9/ninep's File
// and Mutable, and the tree a namespace server hands out as a user's private
// root. Children live in an avl.Tree, so a directory listing is ordered by
// name and therefore identical on every validating node; a map would make
// Render a consensus bug.
//
// Mutable is IN-REALM ONLY. A non-crossing method runs in the caller's frame,
// so a foreign realm calling Create or Write here would be mutating objects it
// does not own. Reads (the ninep.File half) are safe from anywhere, which is
// what makes a memfs tree mountable into somebody else's namespace.
//
// The caller supplies the clock (a block height) on every mutation rather than
// the tree reading chain state itself, so the same tree is exercisable in a
// plain unit test.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This package is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package memfs

import (
	"strings"

	"gno.land/p/nt/avl/v0"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

// FS is a mutable in-memory file tree.
type FS struct {
	root *node
	next uint64 // qid path allocator, unique for this server's lifetime
	uid  string
}

type node struct {
	fs       *FS
	name     string
	perm     ninep.Perm
	qid      ninep.Qid
	data     string
	children *avl.Tree // name -> *node; nil for a plain file
	mtime    int64
	uid      string
	gid      string
	muid     string
}

// New returns an empty file server owned by uid, with its root created at
// block height now.
func New(uid string, now int64) *FS {
	fs := &FS{uid: uid}
	fs.root = fs.newNode("/", ninep.DirPerm, now)
	return fs
}

// Root returns the server's root directory.
func (fs *FS) Root() ninep.File { return fs.root }

// RootMutable returns the root as a Mutable. Only call it from the realm that
// owns this FS.
func (fs *FS) RootMutable() ninep.Mutable { return fs.root }

// Uid returns the owner this server stamps on new files.
func (fs *FS) Uid() string { return fs.uid }

func (fs *FS) newNode(name string, perm ninep.Perm, now int64) *node {
	fs.next++
	qt := ninep.QTFILE
	var kids *avl.Tree
	if perm.IsDir() {
		qt = ninep.QTDIR
		kids = avl.NewTree()
	}
	return &node{
		fs:       fs,
		name:     name,
		perm:     perm,
		qid:      ninep.Qid{Type: qt, Version: 0, Path: fs.next},
		children: kids,
		mtime:    now,
		uid:      fs.uid,
		gid:      fs.uid,
		muid:     fs.uid,
	}
}

// Stat implements ninep.File.
func (n *node) Stat() ninep.Stat {
	length := int64(len(n.data))
	if n.perm.IsDir() {
		length = 0 // 9P reports zero for a directory
	}
	return ninep.Stat{
		Qid:    n.qid,
		Mode:   n.perm,
		Mtime:  n.mtime,
		Length: length,
		Name:   n.name,
		Uid:    n.uid,
		Gid:    n.gid,
		Muid:   n.muid,
	}
}

// Walk implements ninep.File.
func (n *node) Walk(name string) (ninep.File, error) {
	if !n.perm.IsDir() {
		return nil, ninep.ErrNotDir
	}
	if !ninep.ValidName(name) {
		return nil, ninep.ErrBadName
	}
	v := n.children.Get(name) // avl.Get returns ONE value in gno
	if v == nil {
		return nil, ninep.ErrNotExist
	}
	return v.(*node), nil
}

// Read implements ninep.File.
func (n *node) Read(off, count int64) (string, error) {
	if n.perm.IsDir() {
		return "", ninep.ErrIsDir
	}
	return ninep.Slice(n.data, off, count), nil
}

// ReadDir implements ninep.File.
func (n *node) ReadDir() ([]ninep.Stat, error) {
	if !n.perm.IsDir() {
		return nil, ninep.ErrNotDir
	}
	out := []ninep.Stat{}
	n.children.Iterate("", "", func(_ string, v any) bool {
		out = append(out, v.(*node).Stat())
		return false
	})
	return out, nil
}

// Create implements ninep.Mutable.
func (n *node) Create(name string, perm ninep.Perm, now int64) (ninep.File, error) {
	if !n.perm.IsDir() {
		return nil, ninep.ErrNotDir
	}
	if !ninep.ValidName(name) {
		return nil, ninep.ErrBadName
	}
	if n.children.Has(name) {
		return nil, ninep.ErrExist
	}
	child := n.fs.newNode(name, perm, now)
	n.children.Set(name, child)
	n.touch(now)
	return child, nil
}

// Remove implements ninep.Mutable. A non-empty directory is refused, as in
// Plan 9.
func (n *node) Remove(name string) error {
	if !n.perm.IsDir() {
		return ninep.ErrNotDir
	}
	v := n.children.Get(name)
	if v == nil {
		return ninep.ErrNotExist
	}
	child := v.(*node)
	if child.perm.IsDir() && child.children.Size() > 0 {
		return ninep.ErrNotEmpty
	}
	n.children.Remove(name)
	n.touch(n.mtime)
	return nil
}

// Write implements ninep.Mutable. Writing past the end extends the file with
// NUL bytes, as a 9P server does.
func (n *node) Write(off int64, data string, now int64) (int64, error) {
	if n.perm.IsDir() {
		return 0, ninep.ErrIsDir
	}
	if off < 0 {
		off = 0
	}
	if n.perm&ninep.DMAPPEND != 0 {
		off = int64(len(n.data))
	}
	cur := n.data
	if off > int64(len(cur)) {
		cur += strings.Repeat("\x00", int(off)-len(cur))
	}
	end := off + int64(len(data))
	tail := ""
	if end < int64(len(cur)) {
		tail = cur[end:]
	}
	n.data = cur[:off] + data + tail
	n.touch(now)
	return int64(len(data)), nil
}

// Truncate implements ninep.Mutable.
func (n *node) Truncate(size int64, now int64) error {
	if n.perm.IsDir() {
		return ninep.ErrIsDir
	}
	if size < 0 {
		size = 0
	}
	switch {
	case size < int64(len(n.data)):
		n.data = n.data[:size]
	case size > int64(len(n.data)):
		n.data += strings.Repeat("\x00", int(size)-len(n.data))
	}
	n.touch(now)
	return nil
}

// touch bumps the qid version and the mtime. A client that kept a qid can tell
// the file changed without reading it, which is the whole point of Qid.Version.
func (n *node) touch(now int64) {
	n.qid.Version++
	n.mtime = now
	n.muid = n.fs.uid
}

// MkdirAll creates p and every missing parent, and returns the leaf. An
// existing directory is not an error; an existing plain file on the path is.
func (fs *FS) MkdirAll(p string, now int64) (ninep.File, error) {
	cur := fs.root
	for _, e := range ninep.Elems(p) {
		v := cur.children.Get(e)
		if v == nil {
			f, err := cur.Create(e, ninep.DirPerm, now)
			if err != nil {
				return nil, err
			}
			cur = f.(*node)
			continue
		}
		cur = v.(*node)
		if !cur.perm.IsDir() {
			return nil, ninep.ErrNotDir
		}
	}
	return cur, nil
}

// WriteFile creates or replaces the file at p, creating parent directories as
// needed. It is the seeding helper a realm wants at init.
func (fs *FS) WriteFile(p, data string, now int64) error {
	dir, err := fs.MkdirAll(ninep.Dir(p), now)
	if err != nil {
		return err
	}
	name := ninep.Base(p)
	d := dir.(*node)
	v := d.children.Get(name)
	if v == nil {
		f, err := d.Create(name, ninep.FilePerm, now)
		if err != nil {
			return err
		}
		_, err = f.(*node).Write(0, data, now)
		return err
	}
	target := v.(*node)
	if err := target.Truncate(0, now); err != nil {
		return err
	}
	_, err = target.Write(0, data, now)
	return err
}
