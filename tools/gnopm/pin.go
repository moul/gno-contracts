package main

import (
	"fmt"
	"io"
	"strings"
)

// baseRefs are tried in order to find the branch a pin has to be reachable
// from. First one that resolves wins.
var baseRefs = []string{"origin/main", "origin/master", "main", "master"}

// pinTarget is the commit a version gets recorded at, and how it was chosen.
type pinTarget struct {
	Commit string
	Ref    string // the base ref it is reachable from, empty when it is not
	Hash   string
}

// choosePin picks the commit to record a version at.
//
// Not simply HEAD, and this is the subtle part. This repository squash-merges:
// a pull request's commits do not survive onto the default branch, and once
// the branch is deleted those objects are unreachable from any branch or tag,
// so a fresh clone does not have them. A lock pinned to HEAD of a feature
// branch therefore stops resolving the moment the pull request lands, and
// `gnopm verify` fails on the default branch from then on, with nothing left
// to recover the version from.
//
// So the pin goes to a commit that is already on the default branch and holds
// byte-identical content. In the ordinary case that is just the branch tip:
// nothing has touched the package yet on this branch, so the version being
// left behind is exactly what the default branch has. Falling back to the last
// commit that touched the directory covers the case where the tip has moved on
// for unrelated reasons.
//
// If neither matches, the version being pinned genuinely exists nowhere but
// this branch. HEAD is then the only honest answer, and the caller is warned
// that the pin needs the merge to preserve it.
func choosePin(root, dir, wantHash string, w io.Writer) (pinTarget, error) {
	head, err := gitHead(root)
	if err != nil {
		return pinTarget{}, err
	}
	for _, ref := range baseRefs {
		commit, err := gitResolve(root, ref)
		if err != nil {
			continue
		}
		for _, cand := range candidatesOn(root, commit, dir) {
			h, err := hashAtCommit(root, cand, dir)
			if err != nil {
				continue
			}
			if h == wantHash {
				return pinTarget{Commit: cand, Ref: ref, Hash: h}, nil
			}
		}
		// The base exists but holds no matching content: stop looking at
		// further base refs, they are aliases of the same branch.
		break
	}
	if w != nil {
		fmt.Fprintf(w, "warning: %s is pinned to %s, which is not on the default branch yet.\n"+
			"  This repository squash-merges, so that commit will not survive the merge.\n"+
			"  Re-run `gnopm sync` after the change lands, or pin it to a commit that is already upstream.\n",
			dir, short(head))
	}
	return pinTarget{Commit: head, Hash: wantHash}, nil
}

// candidatesOn returns the commits on base worth testing for a directory:
// the tip, then the last commit that actually touched the directory.
func candidatesOn(root, base, dir string) []string {
	out := []string{base}
	if s, err := git(root, "log", "-1", "--format=%H", base, "--", dir); err == nil {
		if c := strings.TrimSpace(s); c != "" && c != base {
			out = append(out, c)
		}
	}
	return out
}
