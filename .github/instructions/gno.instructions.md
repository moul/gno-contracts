---
applyTo: "**/*.gno"
---

# Reviewing a gno contract

In priority order. Each item is a real defect class, not a preference.

## 1. Authority: who is the caller

- The caller is `cur.Previous().Address()`, and **`cur.IsCurrent()` must be checked first**.
  Missing that check means the realm token was never validated.
- **`OriginCaller()` used as an identity is always a finding.** It is the transaction signer,
  not your caller, so any realm the user calls can turn around and act as them. This is the
  confused deputy, and on this chain it is the standard phishing shape. It is legitimate for
  exactly one thing: telling a user call apart from a realm call.
- **`unsafe.PreviousRealm()` inside a realm that declares crossing functions** means the
  check moved somewhere nothing verifies. The `cur` parameter is right there.
- **A read with no `cur realm` sees the CALLER as `unsafe.CurrentRealm()`, not itself**, and
  that reverses silently the moment the function grows a `cur realm` parameter. Never branch
  on it for authorization in either direction.
- **`txlink.Call`, `ui.Action` and `helplink.Func` with no explicit realm resolve their target
  through `unsafe.CurrentRealm()`**, which during a borrowed read is the IMPORTING realm. When
  another realm embeds this one's `Render` (an aggregator, an embeddable block), every action
  link calls the importer instead. It is a finding when the `Render` is meant to be embedded
  or another realm in the tree already imports it; the fix is the explicit path
  (`ui.ActionIn(realmPath, …)`, `txlink.Realm(realmPath).Call(…)`), as `r/moul/reactions` does.
- **A required actor or reason accepted empty.** A library method taking `by address` or
  `reason string` for a state change has to refuse the zero value, or a consumer records an
  approval with no approver (#311: `ReviewZone` with `by == ""`).

## 2. Value

- A balance updated **after** a transfer rather than before.
- A payout loop that one recipient can block. Credit a ledger and let payees withdraw.
- `OriginSend()` read without an `IsUserCall()` guard. `NewBanker` requires
  `rlm.Previous().IsUserCall()`, and `IsUserCall` is literally `pkgPath == ""`, so a realm
  called by another realm cannot forward the envelope and `maketx run` cannot reach a
  payable function at all.
- Integer overflow before a division. `xmath.MulDiv` refuses rather than returning a wrong
  number; a hand-rolled `a*b/c` does not.
- **Rounding direction.** Say which way it rounds and in whose favour, or it is a finding.
- **Who receives the refund.** Deleting an entry returns its storage deposit to whoever signs
  the deleting transaction, not to whoever paid for it. A path where one party deletes
  another's entries is a path where they collect someone else's deposit (`EFFECTIVE_GNO.md`
  § 2.12; #311).
- **Per-address caps are not a bound.** Addresses cost nothing, so "four per address" stops
  nobody: on #311, about 63 fresh addresses at four proposals each filled the global cap and
  every honest call failed after that.
  A limit that protects availability needs a global cap plus something an attacker cannot
  mint for free (a deposit, an allowlist, curator-reserved capacity).

## 3. Permanence: the mistakes that cannot be undone

- Anything a caller typed and the realm stored must be escaped where it becomes markdown
  (`ui.Inline` in prose, `ui.Cell` in a table cell). A realm that ships an unescaped `Render`
  keeps it forever.
- `private = true` is decided once, before the first publish, and neither direction converts
  afterwards. A **private** realm cannot be imported, cannot have its objects referenced, and
  cannot have a value of a type it defines retained by anyone else; the last two are a runtime
  panic, invisible to lint. A redeploy **wipes every package-level variable** and keeps the
  coins.
- **A relative link that repeats the realm's name is dead in a versioned realm.** gnoweb
  serves it at `.../name/v0`, so `./name:tag/x` resolves against the parent to
  `.../name/name:tag/x`. `./v0:tag/x` does resolve, and is not a finding, but goes stale on
  the next version; absolute (`/r/moul/x/name/v0:tag/x`) is the convention here. A test that
  pins the `Render` output pins the dead link too.
- **A new `p/` package's v0 API is the thing that cannot be edited later**, so read its edge
  cases as contract, not polish:
  - a value type holding a pointer **and** a scalar (a tree plus a counter) splits when
    copied: the copies share the tree and not the count. State goes behind one pointer.
  - page and offset arithmetic on a number that arrives from a `Render` path, at the integer
    limit. `(page-1)*size` wraps, and `bptree.IterateByOffset` clamps a negative offset to 0,
    so an overflow returns page 1 instead of nothing.
  - one method answering the same out-of-range condition two ways (`nil` for one page, an
    empty slice for the next), or a doc comment claiming another package's contract that the
    code does not keep. Two packages documenting different answers is not a finding.
  - a callback handed out during iteration that can write to the tree being walked. The
    walk holds a position inside a leaf, so a removal skips the next key; the doc comment
    has to forbid it or the method has to snapshot.
- **A placeholder in a rendered string** (`/r/REPLACE_ADDR/...`) is a dead link forever.
  `gnovet` catches the literal token; a link to a path that does not exist in the tree is
  your half.
- **A rendered shell command interpolating a stored string unquoted** (`gnokey query ...
  -remote ` + url) is a copy-paste command injection on every visitor who runs it. Quote it,
  or validate the value down to a character set that cannot break out (#311).
- **A state machine whose edit path forgets the derived state.** An edit to a reviewed or
  verified record has to invalidate the review and the verification it no longer matches,
  and an edit to a terminal record (retired, rejected) must not overwrite the reason it
  became terminal. #311 had both, in four places.
- A breaking change to a published package needs a new version, not an edit. Removing or
  renaming an exported symbol, changing a signature, changing on-chain behaviour, swapping
  the backing storage.

## 4. Determinism: a varying `Render` is a consensus bug

- A wall clock. `time.Now()` in a realm is the block timestamp.
- An unbroken tie in a sort. Break ties on the address or the key, always.
- **Map iteration order used as a sort.** Gno map iteration IS deterministic, in *insertion*
  order, which is not a sort and is not stable under delete-then-re-add.
- `sort.Slice` does not exist in gno; ordering needs an explicit `sort.Interface`.

## 5. Cost, which is real money here

- An **unbounded container a third party can grow** is an unbounded storage deposit someone
  is paying for.
- A slice that will be deleted from element by element **refunds nothing**: the backing array
  is one persisted object and only dropping the whole slice frees it. Per-element deletion
  with a refund needs a map or a tree.
- A `deque` that anything renders **by index** is quadratic: `Get(i)` walks from the head.
- Storing a live object instead of an encoded string costs a flat +780 bytes per entry, in
  every container.
- **A `Render` or getter that materializes a whole bucket, then slices it.** `vm/qrender`
  runs under a gas limit, so a list that grows past it stops rendering at all; a page that
  collects every match before taking ten is the same bug at a smaller size. Iterate the
  window (`IterateByOffset`) and stop early (#311 drew five findings of this shape).
- `p/nt/avl` is 2,029 bytes per entry against a map's 153 and a B+ tree at fanout 128's 592.
  New code reaching for `avl` is worth a question.

## gno is not Go, and these compile in your head

- **`avl.Get` returns ONE value**; a miss is a nil interface. **`avl.Remove` returns TWO.**
  Opposite rules on neighbouring methods of the same tree.
- **`ufmt` supports no width or padding flags.** `ufmt.Sprintf("%03d", 7)` returns `"7"`,
  silently, which quietly breaks any avl key padded that way.
- **`recover()` cannot catch a panic from a crossing call.** It is a realm abort.
- **A `p/` package can neither declare nor test a crossing function.** The realm token is
  threaded as a later parameter, `func F(_ int, rlm realm, ...)`.
- Every test starts at height **123** and timestamp **1234567890**; only realm state carries
  over between test functions, and the bank does not.
- **`testing.SetRealm` only governs crossing calls made from the frame that called it.** In a
  helper that does not itself cross, it is silently ignored.
