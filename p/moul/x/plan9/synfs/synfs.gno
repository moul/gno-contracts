// Package synfs builds a synthetic, read-only ninep file server whose contents
// are computed by a function at read time.
//
// This is the package that makes the rest of the suite adoptable. Plan 9's
// device drivers are not storage, they are code behind a name: reading
// /dev/time runs a function. A realm that wants to publish its state as a
// browsable tree does the same thing here, in a few lines, and gets ls, cat,
// stat and mountability for free:
//
//	t := synfs.New("dev", "g1...", func() int64 { return runtime.ChainHeight() })
//	t.Root().
//		Add("sysname", func() string { return runtime.ChainID() }).
//		Add("height", func() string { return strconv.FormatInt(runtime.ChainHeight(), 10) })
//
// The tree is READ-ONLY by construction, which is what makes it safe to hand
// to another realm's namespace: every method is free of side effects, so it
// can be called from a frame that does not own these objects.
//
// A synthetic file reports Qid.Version 0 forever. Its contents can change on
// every block, so a version would be a lie; clients that need change detection
// should read the file.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This package is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package synfs

import (
	"gno.land/p/nt/avl/v0"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

// ReadFn computes a whole file.
type ReadFn func() string

// RangeFn serves a 9P read window directly, for files that are cheaper (or
// only possible) to generate a slice at a time, such as an endless one.
type RangeFn func(off, count int64) (string, error)

// Tree owns the qid allocator, the clock and the owner name shared by every
// node in one synthetic server.
type Tree struct {
	root  *Dir
	next  uint64
	clock func() int64
	uid   string
}

// New returns a tree whose root directory is named name, owned by uid, using
// clock (normally the block height) as every node's mtime. clock may be nil,
// in which case the mtime is zero.
func New(name, uid string, clock func() int64) *Tree {
	t := &Tree{clock: clock, uid: uid}
	t.root = t.NewDir(name)
	return t
}

// Root returns the tree's root directory.
func (t *Tree) Root() *Dir { return t.root }

// Uid returns the owner stamped on every node.
func (t *Tree) Uid() string { return t.uid }

func (t *Tree) now() int64 {
	if t.clock == nil {
		return 0
	}
	return t.clock()
}

func (t *Tree) qid(dir bool) ninep.Qid {
	t.next++
	qt := ninep.QTFILE
	if dir {
		qt = ninep.QTDIR
	}
	return ninep.Qid{Type: qt, Version: 0, Path: t.next}
}

// NewDir returns a detached directory belonging to this tree. Attach it with
// AddDir.
func (t *Tree) NewDir(name string) *Dir {
	return &Dir{
		tree:     t,
		name:     name,
		perm:     ninep.DMDIR | 0555,
		qid:      t.qid(true),
		children: avl.NewTree(),
	}
}

// Dir is a synthetic directory. Its children are held in an avl tree, so a
// listing is ordered by name and identical on every node.
type Dir struct {
	tree     *Tree
	name     string
	perm     ninep.Perm
	qid      ninep.Qid
	children *avl.Tree // name -> ninep.File
}

// Add attaches a read-only file computed by fn, mode 0444. It returns the
// directory, so calls chain.
func (d *Dir) Add(name string, fn ReadFn) *Dir {
	return d.AddPerm(name, 0444, fn)
}

// AddPerm is Add with an explicit mode.
func (d *Dir) AddPerm(name string, perm ninep.Perm, fn ReadFn) *Dir {
	whole := fn
	return d.AddRange(name, perm, func(off, count int64) (string, error) {
		return ninep.Slice(whole(), off, count), nil
	})
}

// AddRange attaches a file that serves a read window itself. Use it for a file
// with no natural end, where materialising the whole thing would be wrong.
func (d *Dir) AddRange(name string, perm ninep.Perm, fn RangeFn) *Dir {
	if !ninep.ValidName(name) {
		panic("synfs: invalid file name: " + name)
	}
	d.children.Set(name, &file{
		tree: d.tree,
		name: name,
		perm: perm &^ ninep.DMDIR,
		qid:  d.tree.qid(false),
		fn:   fn,
	})
	return d
}

// AddDir attaches a subdirectory built with Tree.NewDir.
func (d *Dir) AddDir(sub *Dir) *Dir {
	if !ninep.ValidName(sub.name) {
		panic("synfs: invalid directory name: " + sub.name)
	}
	d.children.Set(sub.name, sub)
	return d
}

// AddFile attaches any ninep.File under the given name, which is how a
// synthetic tree splices in a tree served by something else.
func (d *Dir) AddFile(name string, f ninep.File) *Dir {
	if !ninep.ValidName(name) {
		panic("synfs: invalid file name: " + name)
	}
	d.children.Set(name, f)
	return d
}

// Names returns the directory's entries, in order. Useful for a file that
// wants to describe its own directory, as /dev/drivers does.
func (d *Dir) Names() []string {
	out := []string{}
	d.children.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

// Stat implements ninep.File.
func (d *Dir) Stat() ninep.Stat {
	return ninep.Stat{
		Qid:   d.qid,
		Mode:  d.perm,
		Mtime: d.tree.now(),
		Name:  d.name,
		Uid:   d.tree.uid,
		Gid:   d.tree.uid,
		Muid:  d.tree.uid,
	}
}

// Walk implements ninep.File.
func (d *Dir) Walk(name string) (ninep.File, error) {
	if !ninep.ValidName(name) {
		return nil, ninep.ErrBadName
	}
	v := d.children.Get(name)
	if v == nil {
		return nil, ninep.ErrNotExist
	}
	return v.(ninep.File), nil
}

// Read implements ninep.File.
func (d *Dir) Read(off, count int64) (string, error) { return "", ninep.ErrIsDir }

// ReadDir implements ninep.File.
func (d *Dir) ReadDir() ([]ninep.Stat, error) {
	out := []ninep.Stat{}
	d.children.Iterate("", "", func(_ string, v any) bool {
		out = append(out, v.(ninep.File).Stat())
		return false
	})
	return out, nil
}

type file struct {
	tree *Tree
	name string
	perm ninep.Perm
	qid  ninep.Qid
	fn   RangeFn
}

func (f *file) Stat() ninep.Stat {
	// A synthetic file has no stored length. 9P servers for such files report
	// zero rather than run the generator just to measure it, and so does this.
	return ninep.Stat{
		Qid:   f.qid,
		Mode:  f.perm,
		Mtime: f.tree.now(),
		Name:  f.name,
		Uid:   f.tree.uid,
		Gid:   f.tree.uid,
		Muid:  f.tree.uid,
	}
}

func (f *file) Walk(name string) (ninep.File, error) { return nil, ninep.ErrNotDir }

func (f *file) Read(off, count int64) (string, error) { return f.fn(off, count) }

func (f *file) ReadDir() ([]ninep.Stat, error) { return nil, ninep.ErrNotDir }
