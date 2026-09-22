// Package ns is a Plan 9 namespace: a private, mutable mount table over
// gno.land/p/moul/x/plan9/ninep file trees.
//
// This is the idea the rest of the suite exists for. Plan 9's leverage does
// not come from "everything is a file", it comes from every process owning its
// own name-to-resource mapping, so a name can be REPLACED and any service can
// be composed, shadowed, sandboxed or mocked without the program knowing. Gno
// has one global tree and no way to hold a view of it; an Ns is that view.
//
// Bind flags follow bind(2): MREPL replaces, MBEFORE splices the new directory
// in front of the old one, MAFTER behind it, and MCREATE (OR'd onto any of
// them) marks the union member that new files are created in.
//
// Two Plan 9 properties are load-bearing and reproduced deliberately:
//
//   - A union is TOP LEVEL ONLY. Binding /a onto /b unions the two directories
//     at /b; /b/c resolves in whichever member won the walk, and is not itself
//     a union unless something is bound there too.
//   - A bind captures a CHANNEL, not a name. The source is resolved once, at
//     bind time, and the resulting file is what is stored. Rebinding the
//     source afterwards does not retroactively move the target.
//
// ".." is removed lexically before resolution starts and never reaches a
// server, per "Lexical File Names in Plan 9, or Getting Dot-Dot Right".
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This package is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package ns

import (
	"errors"
	"strings"

	"gno.land/p/nt/avl/v0"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

// Flag is a bind(2) mount flag. The low two bits pick the mode; MCREATE is
// OR'd onto it.
type Flag uint32

// Mount flags, with Plan 9's values.
const (
	MREPL   Flag = 0x0000 // replace the old file with the new one
	MBEFORE Flag = 0x0001 // union, new directory first
	MAFTER  Flag = 0x0002 // union, new directory last
	MCREATE Flag = 0x0004 // creates in this union go here
)

func (f Flag) mode() Flag    { return f & 0x0003 }
func (f Flag) creates() bool { return f&MCREATE != 0 }

// String renders the flag as the command-line letters bind(1) uses.
func (f Flag) String() string {
	s := ""
	switch f.mode() {
	case MBEFORE:
		s = "-b"
	case MAFTER:
		s = "-a"
	}
	if f.creates() {
		if s == "" {
			s = "-c"
		} else {
			s += "c"
		}
	}
	return s
}

// Limits. Resolution costs one call per element per union member, and those
// calls may cross a realm boundary, so both are capped rather than trusted.
const (
	MaxUnion = 8 // members in one union
	MaxOps   = 64
)

var (
	// ErrNoRoot means the namespace has nothing bound at "/".
	ErrNoRoot = errors.New("no root in namespace")
	// ErrWideUnion means a bind would exceed MaxUnion members.
	ErrWideUnion = errors.New("union too wide")
	// ErrTooManyOps means the namespace has reached MaxOps bindings.
	ErrTooManyOps = errors.New("too many namespace operations")
	// ErrNotBound means unmount was asked to remove something that is not
	// bound at that name.
	ErrNotBound = errors.New("not bound")
)

// member is one element of a union. A nil file is the placeholder standing for
// "whatever walking to this name would have found", which is how MBEFORE and
// MAFTER keep the original directory in the union.
type member struct {
	file   ninep.File
	create bool
}

type entry struct {
	members []member
}

// Op records one bind or mount, in application order, so that String can print
// the namespace the way Plan 9's ns(1) does.
type Op struct {
	Verb   string // "bind" or "mount"
	Flag   Flag
	Source string
	Target string
}

// Ns is one namespace: a mount table, a working directory, and the ordered
// list of operations that produced them.
type Ns struct {
	table *avl.Tree // cleaned target path -> *entry
	ops   []Op
	cwd   string
}

// New returns a namespace whose root is the given file. The root is the one
// binding that cannot be expressed as a bind of something else, so it is
// installed directly.
func New(root ninep.File) *Ns {
	n := &Ns{table: avl.NewTree(), cwd: "/"}
	n.table.Set("/", &entry{members: []member{{file: root, create: true}}})
	return n
}

// Cwd returns the working directory.
func (n *Ns) Cwd() string { return n.cwd }

// Cd sets the working directory, which must resolve to a directory.
func (n *Ns) Cd(p string) error {
	abs := n.Abs(p)
	st, err := n.Stat(abs)
	if err != nil {
		return err
	}
	if !st.IsDir() {
		return ninep.ErrNotDir
	}
	n.cwd = abs
	return nil
}

// Abs resolves p against the working directory.
func (n *Ns) Abs(p string) string { return ninep.Abs(n.cwd, p) }

func (n *Ns) entry(p string) *entry {
	v := n.table.Get(p)
	if v == nil {
		return nil
	}
	return v.(*entry)
}

// expand substitutes the walk result for the placeholder member.
func expand(ms []member, under []member) []member {
	out := []member{}
	for _, m := range ms {
		if m.file == nil {
			out = append(out, under...)
			continue
		}
		out = append(out, m)
	}
	return out
}

// resolve walks p and returns the union found there, richest form: members
// still carry their create bit, and bound reports whether a mount entry
// applied at the final element.
func (n *Ns) resolve(p string) ([]member, error) {
	root := n.entry("/")
	if root == nil {
		return nil, ErrNoRoot
	}
	cur := expand(root.members, nil)
	if len(cur) == 0 {
		return nil, ErrNoRoot
	}
	elems := ninep.Elems(ninep.Clean(p))
	if len(elems) > ninep.MaxDepth {
		return nil, ninep.ErrTooDeep
	}
	prefix := ""
	for _, e := range elems {
		// First match wins. Walking INTO a union does not produce a union
		// of the members' subdirectories: in Plan 9 a union is top level
		// only, and a walk returns one channel.
		walked := []member{}
		for _, m := range cur {
			f, err := m.file.Walk(e)
			if err == nil {
				walked = append(walked, member{file: f})
				break
			}
		}
		prefix += "/" + e
		next := walked
		if ent := n.entry(prefix); ent != nil {
			next = expand(ent.members, walked)
		}
		if len(next) == 0 {
			return nil, ninep.ErrNotExist
		}
		cur = next
	}
	return cur, nil
}

// Resolve returns every union member visible at p, in search order.
func (n *Ns) Resolve(p string) ([]ninep.File, error) {
	ms, err := n.resolve(n.Abs(p))
	if err != nil {
		return nil, err
	}
	out := []ninep.File{}
	for _, m := range ms {
		out = append(out, m.file)
	}
	return out, nil
}

// Open returns the file a name resolves to: the first member of its union,
// which is the one a walk through this name would reach.
func (n *Ns) Open(p string) (ninep.File, error) {
	fs, err := n.Resolve(p)
	if err != nil {
		return nil, err
	}
	return fs[0], nil
}

// Stat returns the entry for p, with the name replaced by the last element of
// the path as asked for, so that a union member's own name never leaks.
func (n *Ns) Stat(p string) (ninep.Stat, error) {
	f, err := n.Open(p)
	if err != nil {
		return ninep.Stat{}, err
	}
	st := f.Stat()
	st.Name = ninep.Base(n.Abs(p))
	return st, nil
}

// ReadFile reads the whole file at p.
func (n *Ns) ReadFile(p string) (string, error) {
	f, err := n.Open(p)
	if err != nil {
		return "", err
	}
	return ninep.ReadAll(f)
}

// ReadDir lists p. A union directory is the CONCATENATION of its members'
// contents, as in Plan 9, so duplicate names can appear and shadowing is
// visible. Pass unique to collapse them first-wins instead, which is the set
// of names a walk can actually reach.
func (n *Ns) ReadDir(p string, unique bool) ([]ninep.Stat, error) {
	ms, err := n.resolve(n.Abs(p))
	if err != nil {
		return nil, err
	}
	if len(ms) == 1 && !ms[0].file.Stat().IsDir() {
		return nil, ninep.ErrNotDir
	}
	out := []ninep.Stat{}
	seen := map[string]bool{}
	for _, m := range ms {
		ents, err := m.file.ReadDir()
		if err != nil {
			continue // a non-directory member contributes nothing
		}
		for _, e := range ents {
			if unique {
				if seen[e.Name] {
					continue
				}
				seen[e.Name] = true
			}
			out = append(out, e)
		}
	}
	return out, nil
}

// CreateTarget returns the directory that a create at p should happen in.
//
// For a plain directory that is just the directory. For a union it is the
// first member carrying MCREATE, and if no member has it, creation is refused,
// which is bind(2)'s rule.
func (n *Ns) CreateTarget(p string) (ninep.Mutable, error) {
	abs := n.Abs(p)
	ms, err := n.resolve(abs)
	if err != nil {
		return nil, err
	}
	isUnion := n.entry(abs) != nil && len(ms) > 1
	for _, m := range ms {
		if isUnion && !m.create {
			continue
		}
		mu, ok := m.file.(ninep.Mutable)
		if !ok {
			continue // a read-only server, for instance a mounted realm
		}
		if !mu.Stat().IsDir() {
			continue
		}
		return mu, nil
	}
	if isUnion {
		return nil, ninep.ErrNoCreate
	}
	return nil, ninep.ErrPerm
}

// Bind makes source visible at target, as bind(1) does. Both names are
// resolved in THIS namespace, and the source is resolved once: what is stored
// is the file it names today, not the name.
func (n *Ns) Bind(source, target string, flag Flag) error {
	return n.BindVerb("bind", source, target, flag)
}

// BindVerb is Bind with the verb that String should print. Plan 9 spells the
// same operation "bind" or "mount" depending on whether the source is a name
// or a channel, and ns(1) echoes back whichever was used.
func (n *Ns) BindVerb(verb, source, target string, flag Flag) error {
	ms, err := n.resolve(n.Abs(source))
	if err != nil {
		return err
	}
	files := []ninep.File{}
	for _, m := range ms {
		files = append(files, m.file)
	}
	return n.graft(verb, source, target, flag, files)
}

// Mount grafts a file tree that has no name in this namespace yet, which is
// how a service posted by another realm gets in. source is a label, used only
// when printing the namespace.
func (n *Ns) Mount(f ninep.File, source, target string, flag Flag) error {
	return n.graft("mount", source, target, flag, []ninep.File{f})
}

func (n *Ns) graft(verb, source, target string, flag Flag, files []ninep.File) error {
	if len(n.ops) >= MaxOps {
		return ErrTooManyOps
	}
	abs := n.Abs(target)
	// bind(1) requires the target to exist: you can only rebind a name that
	// already resolves to something.
	if _, err := n.resolve(abs); err != nil {
		return err
	}
	add := []member{}
	for _, f := range files {
		add = append(add, member{file: f, create: flag.creates()})
	}

	ent := n.entry(abs)
	var members []member
	switch {
	case ent == nil:
		// The name has never been bound: its current contents are the
		// placeholder. It does NOT carry MCREATE, which is why creating
		// in a freshly unioned directory is refused until some member is
		// bound with -c.
		members = []member{{file: nil}}
	default:
		members = ent.members
	}
	switch flag.mode() {
	case MBEFORE:
		members = append(add, members...)
	case MAFTER:
		members = append(members, add...)
	default: // MREPL: the old file is gone, not unioned
		members = add
	}
	if len(members) > MaxUnion {
		return ErrWideUnion
	}
	n.table.Set(abs, &entry{members: members})
	n.ops = append(n.ops, Op{Verb: verb, Flag: flag, Source: source, Target: abs})
	return nil
}

// Unmount undoes bindings at target. With an empty source it removes every
// binding there, restoring the name to whatever it resolved to originally.
func (n *Ns) Unmount(source, target string) error {
	abs := n.Abs(target)
	ent := n.entry(abs)
	if ent == nil {
		return ErrNotBound
	}
	if source == "" {
		n.table.Remove(abs)
		n.dropOps(abs, "")
		return nil
	}
	ms, err := n.resolve(n.Abs(source))
	if err != nil {
		return err
	}
	kept := []member{}
	removed := false
	for _, m := range ent.members {
		drop := false
		for _, s := range ms {
			if m.file != nil && m.file == s.file {
				drop = true
				break
			}
		}
		if drop {
			removed = true
			continue
		}
		kept = append(kept, m)
	}
	if !removed {
		return ErrNotBound
	}
	if onlyPlaceholders(kept) {
		// Nothing but "whatever was here originally" is left, so the entry
		// is a no-op: drop it rather than leave a phantom binding behind.
		n.table.Remove(abs)
	} else {
		n.table.Set(abs, &entry{members: kept})
	}
	n.dropOps(abs, source)
	return nil
}

func onlyPlaceholders(ms []member) bool {
	for _, m := range ms {
		if m.file != nil {
			return false
		}
	}
	return true
}

func (n *Ns) dropOps(target, source string) {
	kept := []Op{}
	for _, op := range n.ops {
		if op.Target == target && (source == "" || op.Source == source) {
			continue
		}
		kept = append(kept, op)
	}
	n.ops = kept
}

// Ops returns the bindings in application order.
func (n *Ns) Ops() []Op { return n.ops }

// String prints the namespace the way Plan 9's ns(1) does: one line per
// binding, in the order they were applied, then the working directory.
func (n *Ns) String() string {
	var b strings.Builder
	for _, op := range n.ops {
		b.WriteString(op.Verb)
		if f := op.Flag.String(); f != "" {
			b.WriteString(" " + f)
		}
		b.WriteString(" " + quote(op.Source) + " " + quote(op.Target) + "\n")
	}
	b.WriteString("cd " + quote(n.cwd) + "\n")
	return b.String()
}

// quote applies rc quoting: single quotes when the word contains a space or a
// quote, with an embedded quote doubled.
func quote(s string) string {
	if s != "" && !strings.ContainsAny(s, " \t'") {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}
