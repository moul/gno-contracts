// Package wiki is a Wikipedia-shaped wiki engine for gno.land: namespaced
// titles, an append-only revision chain, wikilinks with backlinks, categories,
// redirects, protection levels, line diffs, and markdown rendering.
//
// It is pure: no realm globals, no chain imports. Every call takes the context
// it needs (author address, wall clock, block height) from the caller, so the
// whole engine is unit-testable off-chain. The live demo realm is
// gno.land/r/moul/x/wiki/v0.
//
// # Storage model
//
// A realm write locks a storage deposit proportional to the bytes it adds
// (100ugnot per byte since gnolang/gno#6171), so a wiki that kept every
// revision in full would charge its editors for the whole history forever.
// This engine instead stores a content-addressed spine plus a bounded body
// window:
//
//   - Every revision keeps its metadata permanently: id, parent, author,
//     time, height, summary, byte size, and the SHA-256 of the body. That is
//     roughly 200 bytes, independent of article size.
//   - Only the newest Retention revisions of a page keep their body. Older
//     bodies are evicted (set to ""), which releases their deposit.
//
// An evicted body is not lost: its bytes were an argument of the transaction
// that wrote it, so they remain in the chain's transaction history, and the
// retained hash proves which bytes were the real ones. The realm stops paying
// rent for deep history; the archive lives where archives belong.
//
// # Untrusted markdown
//
// Article bodies are attacker-controlled markdown. Render passes every body
// through gno.land/p/nt/markdown/sanitize/v0 before any wikilink rewriting,
// never after: sanitize escapes "[" to "\\[", so a rewriter that ran first
// would hand its own generated links to the escaper. See links.gno.
package wiki
