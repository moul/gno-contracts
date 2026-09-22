// Package dev is the chain as a Plan 9 device tree.
//
// In Plan 9 a device is not storage, it is code behind a name: reading
// /dev/time runs a function. Everything a gno realm normally reaches through
// an import of chain/runtime is published here as a file instead, so it can be
// read, listed, bound and unioned like anything else:
//
//	cat /dev/sysname     the chain id
//	cat /dev/height      the block height
//	cat /dev/session     what a delegated key is allowed to touch
//
// The tree is posted to gno.land/r/moul/x/plan9/ns's /srv at deploy time, so
// any account can bind it into their own namespace, and nobody has to import
// this realm to use it. That is the cross-realm mount the whole experiment
// turns on: an interface value published by one realm, stored by another, and
// called later from a read-only Render.
//
// It is READ-ONLY, like every synthetic tree: the files have no Write, so
// grafting this into a stranger's namespace cannot be turned into a write
// against this realm.
//
// /dev/session is the one to look at. A gno.land account session is a
// delegated key scoped to a list of path prefixes, which is Plan 9's "the
// namespace IS the capability" rediscovered thirty-four years later. Printing
// it as a file makes that visible.
//
// NOTICE. Plan 9 from Bell Labs is the work of the Computing Science Research
// Center at Bell Labs; the name and the marks are theirs, and the copyright is
// held by the Plan 9 Foundation (https://p9f.org). This realm is not
// affiliated with, endorsed by, or sponsored by them, and contains no Plan 9
// code: it borrows the vocabulary so that the design reads without a glossary,
// and it is an homage, asking what that ecosystem's spirit looks like on a
// chain. Full attribution: NOTICE.md at the root of moul/gno-contracts.
package dev

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
	"time"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
	synfs "gno.land/p/moul/x/plan9/synfs/v0"

	nsrealm "gno.land/r/moul/x/plan9/ns/v0"
)

var tree *synfs.Tree

// docs describes each device, for Render and for /dev/drivers.
var docs = [][2]string{
	{"caller", "pkgpath of the realm that crossed into this read"},
	{"domain", "the chain domain"},
	{"drivers", "this table"},
	{"height", "current block height"},
	{"null", "always empty; the bit bucket"},
	{"random", "sha256 of chain id and height, hex; block-deterministic, NOT unpredictable"},
	{"session", "the calling key's session scope, one AllowPath per line"},
	{"sysname", "the chain id"},
	{"time", "block time, RFC3339"},
	{"user", "the origin caller's address"},
	{"zero", "endless NUL bytes; reads exactly what you ask for"},
}

func init(cur realm) {
	tree = build()
	nsrealm.Post(cross(cur), "dev", tree.Root())
}

func build() *synfs.Tree {
	t := synfs.New("dev", "sys", func() int64 { return runtime.ChainHeight() })
	r := t.Root()

	r.Add("sysname", func() string { return runtime.ChainID() })
	r.Add("domain", func() string { return runtime.ChainDomain() })
	r.Add("height", func() string { return strconv.FormatInt(runtime.ChainHeight(), 10) })
	r.Add("time", func() string { return time.Now().Format(time.RFC3339) })
	r.Add("user", func() string { return unsafe.OriginCaller().String() })
	r.Add("caller", func() string { return unsafe.PreviousRealm().PkgPath() })
	r.Add("null", func() string { return "" })
	r.Add("random", func() string {
		sum := sha256.Sum256([]byte(runtime.ChainID() + ":" +
			strconv.FormatInt(runtime.ChainHeight(), 10)))
		return hex.EncodeToString(sum[:])
	})
	r.Add("session", session)
	r.Add("drivers", drivers)

	// /dev/zero has no end, so it serves the read window itself rather than
	// materialising a value. An unbounded read returns nothing, which is what
	// stops `cat /dev/zero` from being a denial of service.
	r.AddRange("zero", 0444, func(off, count int64) (string, error) {
		if count <= 0 {
			return "", nil
		}
		if count > 4096 {
			count = 4096
		}
		return strings.Repeat("\x00", int(count)), nil
	})
	return t
}

// session prints the calling key's authority. A plain key has none, which is
// itself worth saying out loud.
func session() string {
	pubKeyAddr, expiresAt, allowPaths, isSession := runtime.GetSessionInfo()
	if !isSession {
		var b strings.Builder
		b.WriteString("session no\n")
		b.WriteString("scope full\n")
		return b.String()
	}
	var b strings.Builder
	b.WriteString("session yes\n")
	b.WriteString("key " + pubKeyAddr.String() + "\n")
	b.WriteString("expires " + strconv.FormatInt(expiresAt, 10) + "\n")
	for _, p := range allowPaths {
		b.WriteString("allow " + p + "\n")
	}
	return b.String()
}

func drivers() string {
	var b strings.Builder
	for _, d := range docs {
		b.WriteString(d[0] + "\t" + d[1] + "\n")
	}
	return b.String()
}

// Root returns the device tree, for a realm that would rather import it than
// bind it. Reading it is safe from anywhere; it has no mutating method.
func Root() ninep.File { return tree.Root() }

// Render lists the devices, or reads one.
//
//	Render("")            the table of devices
//	Render("cat/height")  one device's contents
func Render(path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) >= 2 && parts[0] == "cat" {
		name := parts[1]
		f, err := tree.Root().Walk(name)
		if err != nil {
			return "# /dev/" + name + "\n\n```\n" + err.Error() + "\n```\n"
		}
		data, err := ninep.ReadAll(f)
		if err != nil {
			return "# /dev/" + name + "\n\n```\n" + err.Error() + "\n```\n"
		}
		return "# /dev/" + name + "\n\n```\n" + data + "\n```\n\n[all devices](:)\n"
	}
	return renderIndex()
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# /dev\n\n")
	b.WriteString("The chain as a Plan 9 device tree. Each file is a function: reading it ")
	b.WriteString("runs code, so `/dev/height` is never stale.\n\n")
	b.WriteString("Posted to [`r/moul/x/plan9/ns`](/r/moul/x/plan9/ns/v0)'s `/srv` at deploy ")
	b.WriteString("time, so no realm has to import this one to use it:\n\n")
	b.WriteString("```\nbind /srv/dev /dev\n```\n\n")
	b.WriteString("| device | contents |\n|---|---|\n")
	for _, d := range docs {
		b.WriteString("| [`" + d[0] + "`](:cat/" + d[0] + ") | " + d[1] + " |\n")
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
