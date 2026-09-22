package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// The private question, and why a guard asks it rather than a convention.
//
// `private = true` in a realm's gnomod.toml buys exactly one thing: its creator
// may re-add the package AT THE SAME PATH instead of abandoning it for a
// `/vN+1`. It costs three: no other realm may import it, none may hold a
// reference to an object it owns or a value of a type it defines, and a
// redeploy re-runs `init()`, so every package-level variable is back to its
// initializer. AGENTS.md § `private = true` has the measured table.
//
// What makes it a guard and not a note is that it is decided ONCE, and by
// silence. The flag is read off the submitted mempackage at AddPackage time, so
// after the first deploy the door is shut both ways: `checkGnomodConstraints`
// refuses private -> public, and the already-exists gate above it refuses
// public -> private as "package already exists"
// (gno.land/pkg/sdk/vm/keeper.go). `r/moul/faucet` missed it by two minutes and
// is frozen public on mainnet with the flag sitting uselessly in its gnomod.
//
// So the default is private, and a realm that wants to stay importable says so
// in the file, before it ships, with a reason a reader can weigh.

// privateTrueRe matches the `private = true` line of a gnomod.toml.
var privateTrueRe = regexp.MustCompile(`(?m)^[[:space:]]*private[[:space:]]*=[[:space:]]*true`)

// privateAnyRe matches any `private =` declaration, whatever its value. `p/` is
// checked against this one rather than against privateTrueRe: `private = false`
// there is still a package saying something the chain will refuse to hear.
var privateAnyRe = regexp.MustCompile(`(?m)^[[:space:]]*private[[:space:]]*=`)

// publicOptOutRe matches the opt-out: a `# public: <why>` comment line.
//
// A comment rather than `private = false`, because the two are not the same
// statement. The gnomod field is `omitempty`, so `false` and absent serialize
// identically and a reader cannot tell a decision from an oversight. The
// comment can only have been typed on purpose, and it carries the reason.
var publicOptOutRe = regexp.MustCompile(`(?m)^[[:space:]]*#[[:space:]]*public:[[:space:]]*(\S.*?)[[:space:]]*$`)

// minOptOutReason is the floor on an opt-out reason, in characters. The real
// ones in the tree run to a clause ("imported by r/moul/x/plan9/dev"); anything
// under this is "why not" or "see above", which answers nothing.
const minOptOutReason = 20

// cmdGuardPrivate fails if a realm leaves the private question unanswered, or
// if a `p/` package answers it at all.
//
// Four kinds of realm are not asked, because for them the question is not open:
//
//   - archived (`ignore = true`): the toolchain skips them everywhere else too.
//   - mirrored from the monorepo (Upstream set): every byte including the
//     gnomod is a copy of gnolang/gno's, and `make sync` reads any diff as
//     upstream drift. Editing one to satisfy a guard would break that.
//   - superseded: no directory in the tree, so nothing to edit.
//   - already live on mainnet at this exact module path: the chain answered,
//     and it will not take another answer. Flipping the flag there changes
//     nothing on mainnet and is a claim about a realm that cannot honour it.
//
// Note what that last exemption cannot catch: the catalog records that a path
// is taken, not whether the copy the chain holds is private. A realm that
// declares private AFTER its mainnet deploy is exactly the faucet defect, and
// only the publish path can see it. It does not yet.
//
//	go tool gnocontracts guard-private
func cmdGuardPrivate(root string) error {
	m, err := loadManifest(root)
	if err != nil {
		return err
	}
	byPath := make(map[string]*Contract, len(m.Contracts))
	for i := range m.Contracts {
		byPath[m.Contracts[i].PkgPath] = &m.Contracts[i]
	}

	var bad []string
	var private, public, decided, skipped int

	for _, tree := range []string{"p/moul", "r/moul"} {
		base := filepath.Join(root, filepath.FromSlash(tree))
		if !fileExists(base) {
			continue
		}
		realm := strings.HasPrefix(tree, "r/")
		err := filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || d.Name() != "gnomod.toml" {
				return err
			}
			b, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			text := string(b)
			rel, _ := filepath.Rel(root, filepath.Dir(path))
			rel = filepath.ToSlash(rel)

			if !realm {
				// A package cannot be private, and the chain says so at
				// deploy time: "private packages must be realm packages"
				// (checkGnomodConstraints). Catching it here costs a second
				// instead of a parked transaction.
				if privateAnyRe.MatchString(text) {
					bad = append(bad, rel+"/gnomod.toml: a p/ package declares `private`; only realms may")
				}
				return nil
			}

			mod, err := parseModule(path)
			if err != nil {
				return err
			}
			c := byPath[mod]
			switch {
			case parseModuleIgnore(path), c != nil && c.Upstream != "", c != nil && c.Superseded:
				skipped++
				return nil
			case c != nil && c.Published["mainnet"].Uploaded:
				decided++
				return nil
			}

			switch {
			case privateTrueRe.MatchString(text):
				private++
			case publicOptOutRe.MatchString(text):
				reason := publicOptOutRe.FindStringSubmatch(text)[1]
				if len(reason) < minOptOutReason {
					bad = append(bad, fmt.Sprintf(
						"%s/gnomod.toml: opt-out reason is %d characters, under the %d minimum: %q",
						rel, len(reason), minOptOutReason, reason))
					return nil
				}
				public++
			default:
				bad = append(bad, rel+"/gnomod.toml: neither `private = true` nor a `# public: <why>` line")
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	if len(bad) > 0 {
		sort.Strings(bad)
		return failf("guard-private FAIL — realm(s) that never answered the private question", bad,
			"A realm is private by default: add `private = true` to its gnomod.toml, so\n"+
				"you can redeploy it at the same path instead of burning a /vN+1.\n\n"+
				"If another realm must import it, register objects with it, or hand it\n"+
				"values of its types, opt out instead with a line saying why:\n\n"+
				"    # public: imported by r/moul/x/plan9/dev\n\n"+
				"Decide it now: the first deploy shuts the door both ways, forever.\n"+
				"See AGENTS.md § `private = true`.")
	}
	fmt.Printf("guard-private: %d realm(s) answered (%d private, %d public with a reason); "+
		"%d already decided on chain, %d not asked\n", private+public, private, public, decided, skipped)
	return nil
}
