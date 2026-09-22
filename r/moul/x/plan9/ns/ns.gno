// Package ns is a Plan 9 namespace server for gno.land.
//
// Every account gets a private, persistent namespace: its own RAM root plus a
// mount table it alone controls. Realms publish file trees into /srv, accounts
// bind those trees wherever they like, and a read-only rc shell renders the
// whole thing in gnoweb.
//
// This is the part of Plan 9 that gno does not otherwise have. The chain has a
// single global tree of realm paths that looks the same to everybody; here a
// name means what YOU bound it to. Composing two realms that were never
// written to work together stops being a redeploy and becomes a transaction:
//
//	gnokey maketx call -pkgpath gno.land/r/moul/x/plan9/ns/v0 -func Exec \
//	  -args 'bind -ac /srv/dev /dev; echo hello > /tmp/greeting'
//
// SECURITY. Mounted trees are READ-ONLY by construction: ninep.File has no
// mutating method, so grafting a foreign realm's tree into your namespace
// cannot be turned into a write against that realm. Writes only ever reach a
// memfs tree this realm created for you. A crossing write method would mint
// THIS realm's frame for the callee, which is the confused-deputy shape that
// r/gov/dao's Executor relies on deliberately and p/nt/grc20's Teller refuses
// deliberately; it is out of scope for v0. See moul/gno-contracts#136.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This realm is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package ns

import (
	"chain/runtime"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"

	"gno.land/p/moul/realmpath/v0"

	memfs "gno.land/p/moul/x/plan9/memfs/v0"
	ninep "gno.land/p/moul/x/plan9/ninep/v0"
	nspkg "gno.land/p/moul/x/plan9/ns/v0"
	rc "gno.land/p/moul/x/plan9/rc/v0"
)

// DemoKey names the namespace gnoweb browses when no ?u= is given. It is a
// plain string rather than an address so it can never collide with one.
const DemoKey = "demo"

type service struct {
	file  ninep.File
	owner string  // pkgpath of the realm that posted it
	addr  address // that realm's address
	since int64   // block height of the posting
}

type space struct {
	fs *memfs.FS
	ns *nspkg.Ns
}

var (
	services = avl.NewTree() // name -> *service
	spaces   = avl.NewTree() // address string (or DemoKey) -> *space
)

func init() {
	seedDemo()
}

// ---------------------------------------------------------------- /srv

// srvDir is the synthetic directory that makes posted services reachable by
// name. It is written out by hand rather than built with synfs because its
// contents change as realms post, and because implementing ninep.File
// directly is meant to look easy: four methods, no state of its own.
type srvDir struct{}

func (d *srvDir) Stat() ninep.Stat {
	return ninep.Stat{
		Qid:   ninep.Qid{Type: ninep.QTDIR, Path: 1},
		Mode:  ninep.DMDIR | 0555,
		Mtime: runtime.ChainHeight(),
		Name:  "srv",
		Uid:   "sys",
		Gid:   "sys",
		Muid:  "sys",
	}
}

func (d *srvDir) Walk(name string) (ninep.File, error) {
	if !ninep.ValidName(name) {
		return nil, ninep.ErrBadName
	}
	v := services.Get(name)
	if v == nil {
		return nil, ninep.ErrNotExist
	}
	return v.(*service).file, nil
}

func (d *srvDir) Read(off, count int64) (string, error) { return "", ninep.ErrIsDir }

func (d *srvDir) ReadDir() ([]ninep.Stat, error) {
	out := []ninep.Stat{}
	services.Iterate("", "", func(k string, v any) bool {
		st := v.(*service).file.Stat()
		st.Name = k // the posted name, not whatever the server calls its root
		out = append(out, st)
		return false
	})
	return out, nil
}

var srvRoot = &srvDir{}

// ---------------------------------------------------------------- posting

// Post publishes a file tree under name in /srv, where any account can bind
// it. The posting realm is recorded and is the only one that may Unpost.
//
// Names are first come, first served, which is fine for an experiment and
// would not be for anything else.
func Post(cur realm, name string, f ninep.File) {
	if !cur.IsCurrent() {
		panic("post: cur is not the caller's live realm")
	}
	if !ninep.ValidName(name) {
		panic("post: " + ninep.ErrBadName.Error())
	}
	if f == nil {
		panic("post: nil file server")
	}
	prev := cur.Previous()
	if existing := services.Get(name); existing != nil {
		if existing.(*service).owner != prev.PkgPath() {
			panic("post: " + name + " is already posted by " + existing.(*service).owner)
		}
	}
	services.Set(name, &service{
		file:  f,
		owner: prev.PkgPath(),
		addr:  prev.Address(),
		since: runtime.ChainHeight(),
	})
}

// Unpost withdraws a service. Only the realm that posted it may do so.
func Unpost(cur realm, name string) {
	if !cur.IsCurrent() {
		panic("unpost: cur is not the caller's live realm")
	}
	v := services.Get(name)
	if v == nil {
		panic("unpost: " + ninep.ErrNotExist.Error())
	}
	if v.(*service).owner != cur.Previous().PkgPath() {
		panic("unpost: " + name + " belongs to " + v.(*service).owner)
	}
	services.Remove(name)
}

// Services lists the posted service names, in order.
func Services() []string {
	out := []string{}
	services.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

// ---------------------------------------------------------------- namespaces

// newSpace builds the default namespace, which is this chain's /lib/namespace:
// a private ram root, the mount points that Plan 9 requires to exist before
// anything can be bound onto them, /srv mounted, and /dev bound from it when a
// device server has been posted.
func newSpace(owner string) *space {
	now := runtime.ChainHeight()
	fs := memfs.New(owner, now)
	fs.MkdirAll("/srv", now)
	fs.MkdirAll("/dev", now)
	fs.MkdirAll("/tmp", now)

	n := nspkg.New(fs.Root())
	n.Mount(srvRoot, "#s", "/srv", nspkg.MREPL)
	if services.Has("dev") {
		n.Bind("/srv/dev", "/dev", nspkg.MREPL)
	}
	return &space{fs: fs, ns: n}
}

func spaceFor(key string) *space {
	if v := spaces.Get(key); v != nil {
		return v.(*space)
	}
	sp := newSpace(key)
	spaces.Set(key, sp)
	return sp
}

func peek(key string) *space {
	if v := spaces.Get(key); v != nil {
		return v.(*space)
	}
	return nil
}

// seedDemo builds the namespace gnoweb shows by default. It is deliberately
// reproducible: an example test resets it before rendering.
func seedDemo() {
	spaces.Remove(DemoKey)
	sp := spaceFor(DemoKey)
	now := runtime.ChainHeight()
	sp.fs.WriteFile("/tmp/greeting", "hello from a namespace\n", now)
	sp.fs.MkdirAll("/usr/glenda/bin", now)
	sp.fs.WriteFile("/usr/glenda/bin/rc", "#!/bin/rc\n", now)
	sp.fs.MkdirAll("/bin", now)
	sp.fs.WriteFile("/bin/ls", "system ls\n", now)
	sp.ns.Bind("/usr/glenda/bin", "/bin", nspkg.MAFTER|nspkg.MCREATE)
	sp.ns.Cd("/usr/glenda")
}

// ResetDemo rebuilds the demo namespace. Anyone may call it: it is a demo, and
// the alternative is a demo that the first visitor ruins for everybody.
func ResetDemo(cur realm) { seedDemo() }

// ---------------------------------------------------------------- shell

// Exec runs a command line against the CALLER's namespace and returns its
// output. The namespace belongs to cur.Previous().Address(), so a user gets
// theirs and a realm gets its own.
//
// An error panics, so a half-applied command line reverts with the
// transaction rather than leaving a namespace nobody asked for.
func Exec(cur realm, line string) string {
	if !cur.IsCurrent() {
		panic("exec: cur is not the caller's live realm")
	}
	key := cur.Previous().Address().String()
	sp := spaceFor(key)
	sh := rc.New(sp.ns, rc.ReadWrite, runtime.ChainHeight)
	out, err := sh.Run(line)
	if err != nil {
		panic(err.Error())
	}
	return out
}

// Reset discards the caller's namespace, so the next use rebuilds the default.
func Reset(cur realm) {
	if !cur.IsCurrent() {
		panic("reset: cur is not the caller's live realm")
	}
	spaces.Remove(cur.Previous().Address().String())
}

// Run executes a READ-ONLY command line against key's namespace. It is the
// query side of Exec: no transaction, no writes, safe from Render.
func Run(key, line string) (string, error) {
	sp := peek(key)
	if sp == nil {
		return "", errors.New("no namespace for " + key)
	}
	sh := rc.New(sp.ns, rc.ReadOnly, runtime.ChainHeight)
	return sh.Run(line)
}

// Namespace returns key's mount table, in ns(1) format.
func Namespace(key string) string {
	sp := peek(key)
	if sp == nil {
		return ""
	}
	return sp.ns.String()
}

// Keys lists the namespaces that exist, in order.
func Keys() []string {
	out := []string{}
	spaces.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

// ---------------------------------------------------------------- render

// Render browses a namespace.
//
//	Render("")                  overview, posted services, how to drive it
//	Render("ns?u=<key>")        the mount table
//	Render("ls/bin?u=<key>")    a directory listing (ls -l)
//	Render("cat/tmp/greeting")  a file
//	Render("stat/bin")          the 9P stat, with the union width
//	Render("walk/bin/rc")       how each element of a path resolves
//	Render("rc?c=<command>")    any read-only rc command line
//
// ?u= selects the namespace; it defaults to the demo one.
func Render(path string) string {
	req := realmpath.Parse(path)
	key := req.Query.Get("u")
	if key == "" {
		key = DemoKey
	}
	parts := req.PathParts()
	if len(parts) == 0 || parts[0] == "" {
		return renderHome(key)
	}

	cmd := parts[0]
	rest := "/" + strings.Join(parts[1:], "/")
	var line string
	switch cmd {
	case "ns":
		return renderCmd(key, "ns", "ns")
	case "ls":
		line = "ls -l " + quote(rest)
	case "cat":
		line = "cat " + quote(rest)
	case "stat":
		line = "stat " + quote(rest)
	case "walk":
		line = "walk " + quote(rest)
	case "rc":
		line = req.Query.Get("c")
		if line == "" {
			line = "help"
		}
	default:
		return "# 404\n\nunknown command `" + cmd + "`. Try `ls`, `cat`, `stat`, `walk`, `ns` or `rc?c=...`.\n"
	}
	return renderCmd(key, line, cmd+" "+rest)
}

func renderCmd(key, line, title string) string {
	var b strings.Builder
	b.WriteString("# " + title + "\n\n")
	b.WriteString("namespace: `" + key + "`\n\n")
	out, err := Run(key, line)
	if err != nil {
		b.WriteString("```\n" + err.Error() + "\n```\n")
	} else if out == "" {
		b.WriteString("_(no output)_\n")
	} else {
		b.WriteString("```\n" + out + "```\n")
	}
	b.WriteString("\n[namespace](:ns?u=" + key + ") · [root](:ls?u=" + key +
		") · [home](:)\n")
	return b.String()
}

func renderHome(key string) string {
	var b strings.Builder
	b.WriteString("# plan9: namespaces for gno\n\n")
	b.WriteString("A Plan 9 namespace server. Every account owns a private mount table over ")
	b.WriteString("[9P-shaped](https://9p.io/sys/doc/9.html) file trees: realms post trees ")
	b.WriteString("into `/srv`, you `bind` them where you want them, and a name means what ")
	b.WriteString("*you* bound it to.\n\n")

	b.WriteString("## /srv\n\n")
	if services.Size() == 0 {
		b.WriteString("_No service is posted yet._\n\n")
	} else {
		b.WriteString("| name | posted by | since |\n|---|---|---|\n")
		services.Iterate("", "", func(k string, v any) bool {
			s := v.(*service)
			b.WriteString("| `" + k + "` | [`" + s.owner + "`](" +
				strings.TrimPrefix(s.owner, "gno.land") + ") | " +
				strconv.FormatInt(s.since, 10) + " |\n")
			return false
		})
		b.WriteString("\n")
	}

	b.WriteString("## The demo namespace\n\n")
	b.WriteString("```\n" + Namespace(DemoKey) + "```\n\n")
	b.WriteString("`/bin` is a union: the system `/bin` first, then `/usr/glenda/bin`, ")
	b.WriteString("with `-c` so new files land in the second. Listing it shows both members ")
	b.WriteString("because a Plan 9 union is a concatenation, so shadowing stays visible.\n\n")
	b.WriteString("- [ns](:ns) · [ls /](:ls) · [ls /bin](:ls/bin) · ")
	b.WriteString("[cat /tmp/greeting](:cat/tmp/greeting) · [walk /bin/rc](:walk/bin/rc)\n")
	b.WriteString("- any read-only command: [`rc?c=ls -l /srv`](:rc?c=ls%20-l%20/srv)\n\n")

	b.WriteString("## Your own namespace\n\n")
	b.WriteString("```\n")
	b.WriteString("gnokey maketx call -pkgpath gno.land/r/moul/x/plan9/ns/v0 \\\n")
	b.WriteString("  -func Exec -args 'bind -ac /srv/dev /dev; echo hi > /tmp/f'\n")
	b.WriteString("```\n\n")
	b.WriteString("Then browse it with `?u=<your address>`. `Reset` throws it away.\n\n")

	b.WriteString("## Namespaces\n\n")
	keys := Keys()
	for _, k := range keys {
		b.WriteString("- [`" + k + "`](:ns?u=" + k + ")\n")
	}
	b.WriteString("\nDesign and analysis: ")
	b.WriteString("[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).\n")
	b.WriteString("\n_Not affiliated with Plan 9. Plan 9 from Bell Labs is the ")
	b.WriteString("work of the Computing Science Research Center at Bell Labs; the name ")
	b.WriteString("and the marks are theirs, and the copyright is held by the ")
	b.WriteString("[Plan 9 Foundation](https://p9f.org). This realm borrows the ")
	b.WriteString("vocabulary and none of the code: it is an homage, asking what that ")
	b.WriteString("ecosystem's spirit looks like on a chain._\n")
	return b.String()
}

// quote wraps a path for rc if it needs it.
func quote(s string) string {
	if !strings.ContainsAny(s, " \t'") {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}
