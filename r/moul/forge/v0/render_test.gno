package forge

// Every route is pinned by an example: a realm's Render is its whole public
// surface, and output that varies between identical calls is a consensus bug.
// Examples run after every Test, so each one re-seeds the state it renders.

// ExampleRender pins the forge home page.
func ExampleRender() {
	seedFixture()
	print(Render(""))
	// Output:
	// # Forge
	//
	// An on-chain software forge. The objects stay in git; the chain keeps the part a forge is trusted for: which object a ref points at, in what order, on whose authority, and what was reviewed before it moved.
	//
	// **Repos:** 1
	//
	// | repo | refs | issues | changes | log |
	// | --- | ---: | ---: | ---: | ---: |
	// | [moul/forge](/r/moul/forge/v0:moul/forge) | 1 | 1/1 | 1/1 | 2 |
	//
	// [Create a repo](/r/moul/forge/v0$help&func=CreateRepo) · [How it works](/r/moul/forge/v0:help)
}

// ExampleRenderRepo pins a repo overview.
func ExampleRenderRepo() {
	seedFixture()
	print(Render("moul/forge"))
	// Output:
	// # moul/forge
	//
	// an on chain software forge
	//
	// - **Default ref:** `refs/heads/main` → `bbbbbbbbbbbb`
	// - **Merge policy:** 1 writer approval(s), self-approval off
	// - **Members:** 3
	// - **Log head:** `07ca3613cc68e1dc`
	// - **Fetch from:** `https://github.com/moul/gno-contracts.git`
	//
	// ## Refs
	//
	// - `refs/heads/main` → `bbbbbbbbbbbb` · block 102 · [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94)
	//
	// ## Recent log
	//
	// - `#1` **update** `refs/heads/main` `aaaaaaaaaaaa` → `bbbbbbbbbbbb` · block 102 · [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94) · add the log
	// - `#0` **create** `refs/heads/main` (none) → `aaaaaaaaaaaa` · block 101 · [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94) · initial import
	//
	// [Full log, 2 entries](/r/moul/forge/v0:moul/forge/log)
	//
	// ## Open change requests
	//
	// - [\!0 record every ref move](/r/moul/forge/v0:moul/forge/changes/0) · **open** · `refs/heads/main` · 1/1 approvals
	//
	// [All changes, 1 total](/r/moul/forge/v0:moul/forge/changes) · [Propose a change](/r/moul/forge/v0$help&func=OpenChange&repoID=moul%2Fforge)
	//
	// ## Open issues
	//
	// - [\#0 force pushes are invisible](/r/moul/forge/v0:moul/forge/issues/0) · **open** · [g1v4mx2h6lta047h6lta047h6lta047h6lslgc76](/u/g1v4mx2h6lta047h6lta047h6lta047h6lslgc76) · 1 replies
	//
	// [All issues, 1 total](/r/moul/forge/v0:moul/forge/issues) · [Open an issue](/r/moul/forge/v0$help&func=OpenIssue&repoID=moul%2Fforge)
}

// ExampleRenderLog pins the reference log.
func ExampleRenderLog() {
	seedFixture()
	print(Render("moul/forge/log"))
	// Output:
	// # moul/forge: reference log
	//
	// Append-only and hash-chained: every entry commits to the one before it, so pinning the head digest anywhere off chain pins this whole history.
	//
	// **Head:** `07ca3613cc68e1dc` · **Entries:** 2
	//
	// - `#1` **update** `refs/heads/main` `aaaaaaaaaaaa` → `bbbbbbbbbbbb` · block 102 · [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94) · add the log
	// - `#0` **create** `refs/heads/main` (none) → `aaaaaaaaaaaa` · block 101 · [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94) · initial import
}

// ExampleRenderIssue pins one issue.
func ExampleRenderIssue() {
	seedFixture()
	print(Render("moul/forge/issues/0"))
	// Output:
	// # #0 force pushes are invisible
	//
	// **open** · opened at block 103 by [g1v4mx2h6lta047h6lta047h6lta047h6lslgc76](/u/g1v4mx2h6lta047h6lta047h6lta047h6lslgc76)
	//
	// **Labels:** `bug`
	//
	// A maintainer can rewrite a branch and nothing records it\.
	//
	// ## Replies (1)
	//
	// - [g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu](/u/g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu) at block 104: that is what the log is for
	//
	// [Reply](/r/moul/forge/v0$help&func=CommentIssue&issueID=0&repoID=moul%2Fforge) · [Close](/r/moul/forge/v0$help&func=CloseIssue&issueID=0&repoID=moul%2Fforge) · [Back to issues](/r/moul/forge/v0:moul/forge/issues)
}

// ExampleRenderChange pins one change request.
func ExampleRenderChange() {
	seedFixture()
	print(Render("moul/forge/changes/0"))
	// Output:
	// # !0 record every ref move
	//
	// **open** · opened at block 105 by [g1vdshymmvta047h6lta047h6lta047h6l2asz94](/u/g1vdshymmvta047h6lta047h6lta047h6l2asz94)
	//
	// - **Head:** `cccccccccccc` (from this repo `refs/heads/feat`)
	// - **Target:** `refs/heads/main` → `bbbbbbbbbbbb`
	// - **Approvals:** 1 of 1 required
	// - **Blocking:** 0
	//
	// closes 0
	//
	// ## Reviews (1)
	//
	// - [g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu](/u/g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu): **approve** on `cccccccccccc`: lgtm
	//
	// ## Replies (0)
	//
	// None yet.
	//
	// [Review](/r/moul/forge/v0$help&func=ReviewChange&changeID=0&repoID=moul%2Fforge&verdict=approve) · [Reply](/r/moul/forge/v0$help&func=CommentChange&changeID=0&repoID=moul%2Fforge) · [Merge](/r/moul/forge/v0$help&func=MergeChange&changeID=0&expectedTargetOID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&repoID=moul%2Fforge) · [Back to changes](/r/moul/forge/v0:moul/forge/changes)
}

// ExampleRenderNotFound pins an unknown repo.
func ExampleRenderNotFound() {
	seedFixture()
	print(Render("moul/nope"))
	// Output:
	// # Not found
	//
	// no repo `moul/nope`.
	//
	// [Back to the forge](/r/moul/forge/v0)
}
