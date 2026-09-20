package main

import (
	"os"
	"strings"
)

// Detection, so that flags stay optional.
//
// The rule this file exists to enforce: if gnopm can work something out, it
// works it out. A flag is an admission that the tool could not, and every
// required flag is friction paid on every invocation forever. `-upstream` was
// added to `verify` before this existed, and CI had to pass it explicitly,
// which is exactly the shape of thing that should never have shipped.

// upstreamRef returns the ref that pinned commits must be reachable from, and
// whether one could be determined at all.
//
// In order of confidence:
//
//  1. an explicit value, because the caller always wins;
//  2. the pull request's base branch, when running in one. GitHub Actions sets
//     GITHUB_BASE_REF only on pull_request events, which is exactly when the
//     check applies;
//  3. whatever origin/HEAD points at, the repository's real default branch,
//     which is not always main;
//  4. origin/main, then origin/master.
//
// Returns "" when none of those resolve, and callers then skip the check
// rather than guessing: a repository with no remote is a legitimate place to
// work, and refusing to operate there would be worse than not checking.
func upstreamRef(root, explicit string) string {
	if explicit != "" {
		return explicit
	}
	if base := strings.TrimSpace(os.Getenv("GITHUB_BASE_REF")); base != "" {
		if r := "origin/" + base; refExists(root, r) {
			return r
		}
	}
	if s, err := git(root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"); err == nil {
		if r := strings.TrimPrefix(strings.TrimSpace(s), "refs/remotes/"); r != "" && refExists(root, r) {
			return r
		}
	}
	for _, r := range []string{"origin/main", "origin/master"} {
		if refExists(root, r) {
			return r
		}
	}
	return ""
}

// pinBaseRef is the ref a new pin should prefer to point at.
//
// Not the same question as upstreamRef, and conflating them broke a test that
// was right to break. upstreamRef answers "will this commit survive the
// merge", which is meaningless without a remote, so it declines to guess. This
// answers "what is the most stable commit that holds this content", and in a
// repository with no remote the local default branch is a perfectly good
// answer: it is still the thing other branches are cut from.
func pinBaseRef(root string) string {
	if r := upstreamRef(root, ""); r != "" {
		return r
	}
	for _, r := range []string{"main", "master"} {
		if refExists(root, r) {
			return r
		}
	}
	return ""
}

func refExists(root, ref string) bool {
	_, err := gitResolve(root, ref)
	return err == nil
}

// onUpstream reports whether HEAD is the upstream ref itself. Running the
// stranded-pin check against your own branch is meaningless, and on the
// default branch every pin is upstream by definition.
func onUpstream(root, ref string) bool {
	if ref == "" {
		return false
	}
	head, err := gitResolve(root, "HEAD")
	if err != nil {
		return false
	}
	up, err := gitResolve(root, ref)
	return err == nil && head == up
}
