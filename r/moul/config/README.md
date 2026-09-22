# `gno.land/r/moul/config`

moul's settings, plus the manager list that decides who may change them. One
realm the others read, so a value that several contracts share lives in one
place and moving it is a transaction rather than a redeploy of each.

## Settings

```go
func Set(cur realm, key, value string)   // manager only; aborts otherwise
func Unset(cur realm, key string)        // manager only; aborts on a missing key
func Get(key string) string              // "" when unset
func GetOr(key, fallback string) string  // what a consumer should call
func Has(key string) bool
func Keys() []string
func Size() int
func SettingsRevision() int
func Manifest() string                   // the whole config in one qeval read
```

A key is 1 to 64 bytes of `[a-z0-9._-]`, dot-namespaced by convention
(`mygnoscan.url`). A value is capped at 1024 bytes: this realm holds settings,
not content, and storage is paid for and never refunded. Every write emits a
`ConfigSet` / `ConfigUnset` event, so the history of a setting is readable from
an indexer without a call per key.

**The generic API is the point.** A new setting is a new key, which is a
transaction. Only a change to the *shape* of this realm needs a version bump,
and a bump is expensive here: the path changes, so every realm importing the
old one keeps reading the old one until it is itself redeployed. Reach for a
key before reaching for a typed accessor.

### Why the settings functions abort instead of returning an error

The manager functions below return `error`. A returned error from a realm call
leaves the transaction **successful**: the caller sees a green receipt and
walks away believing the write landed, while every realm reading that key keeps
serving the old value. For a configuration realm that is the one outcome worth
ruling out, so `Set` and `Unset` abort. The manager functions predate that
reasoning and are frozen on chain at `v0`; the new surface does not inherit it.

## The notice blocks

Two strings a realm drops at the top and the bottom of its `Render`, empty by
default, so a warning, a changelog line or a bit of news can go on every realm
at once or on one of them.

```go
func Render(path string) string {
	return config.TopBlock() + body + config.BottomBlock()
}
```

Set them with the ordinary `Set`, which is what keeps this realm's surface from
growing a function per idea:

```sh
Set block.top            "> Chain migration on Tuesday."    # every realm
Set block.top@r/moul/gns "> v2 shipped, see the changelog"  # this one only
Unset block.top                                             # back to silence
```

`TopBlock` shows **three** things when they exist, in this order, separated by
blank lines: the pause banner, the global message, then this realm's own. Both
messages, not one overriding the other: a chain-wide warning and a per-realm
changelog are different messages, and dropping either because the other exists
is the surprising behaviour.

When there is nothing to say it returns `""`, so a realm that concatenates it
unconditionally renders byte-for-byte what it rendered before.

## Pausing

```sh
Set pause              "paused: incident, back in an hour"  # everything
Set pause@r/moul/gns   "readonly"                           # one realm
Unset pause                                                 # running again
```

```go
func Post(cur realm, body string) {
	config.AssertWritable()   // aborts while ReadOnly or Paused
	...
}
```

Three levels (`running`, `readonly`, `paused`, each optionally `: <reason>`),
because taking a realm fully offline hides the thing people came to read while
most incidents only need the writes stopped. The levels, the fail-closed parse
and the precedence rule live in
[`p/moul/pausable`](../../../p/moul/pausable); this realm is the storage and
the wiring.

Two properties worth knowing:

- **A global pause cannot be defeated by a per-realm setting.** The two combine
  with `pausable.Strictest`, so a stale `pause@r/moul/foo` of `running` does
  not re-open that realm during a global halt. Exempting one realm is therefore
  not expressible: clear the global and set the others.
- **A pause value is validated on write.** `pausable.MustParse` fails closed, so
  an unvalidated typo would take every realm offline at the next render.
  `Set` refuses anything the reader could not understand, which turns that into
  a failed transaction the writer sees immediately.

`TopBlock` already carries the pause banner, so guarding writes with
`AssertWritable` is enough to also explain the refusal on the page.

## Zero-argument or explicit

Every helper comes in two forms: `TopBlock()` names the realm calling in,
`TopBlockFor(pkgPath)` names one you pass.

The zero-argument form works because these are plain reads with **no `cur realm`
parameter**, so gno runs them borrowed, opens no realm frame, and
`unsafe.CurrentRealm()` reports the caller rather than this realm. Measured in
the test harness on 2026-09-22 and pinned by a test.

Use the explicit form from a crossing function, where there is a realm frame
and the answer would be that function's realm, or when asking about a realm
other than your own. **Do not add a `cur realm` parameter to any of the
zero-argument helpers**: it would silently start answering
`gno.land/r/moul/config` for every caller.

## Versions: v2 relays to v1, never the other way

This realm is public, so its path is permanent and a new API means a new
version at a new path. Left alone that fragments everything: a realm importing
v1 and a realm importing v2 would read two different member lists and two
different pause switches.

Delegation fixes it, and it only runs one way. A version can import what
already existed when it was written, never what does not exist yet. So **the
state stays in the oldest version that has it** and every later version is a
thin relay:

```
v3  ->  v2  ->  v1   (the root: settings, pause, managers, proxies)
```

A realm importing v1, v2 or v3 reads the same state whichever door it came
through. `v0` cannot take part: it is already on chain and has no settings
store, so it keeps answering for its own member list and nothing else.

Writing v2: it holds no state, forwards reads directly, and forwards writes
with the address it was called by.

```go
func Set(cur realm, key, value string) {
	config.SetAs(cross(cur), cur.Previous().Address(), key, value)
}

func Get(key string) string { return config.Get(key) }
```

Then once, from a manager: `AllowProxy gno.land/r/moul/config/v2`.

**A proxy is trusted to say who is asking, not to decide whether they may.**
`SetAs` still puts the principal through the `Authorizer`, so the member list
stays the single answer to "who may change config" for every version at once,
and adding a manager works through v2 and v3 with no further deploys. It is not
a boundary against the proxy's own code, and does not need to be: the same
person deploys both, registration is deliberate, and `RevokeProxy` is
immediate. What it buys is that v2 never carries a copy of the member list, so
the two can never disagree.

`AllowProxy` only accepts `gno.land/r/moul/config/vN`, so a fat-fingered path
cannot become a standing write grant to an unrelated realm.

## The explorer accessors

```go
func MygnoscanURL() string                  // the configured base, or the package default
func Scanner() mygnoscan.Scanner            // a configured link builder
func MygnoscanFor(pkgPath string) string    // a realm's explorer page
func MygnoscanFooter(pkgPath string) string // the markdown line for a Render
```

This is the worked example of the whole idea. A realm renders
`config.MygnoscanFooter("gno.land/r/moul/mything")` in its footer; moul points
every one of them at a different explorer with:

```sh
gnokey maketx call -pkgpath gno.land/r/moul/config/v1 -func Set   -args mygnoscan.url -args https://scan.example.com   -gas-fee 1000000ugnot -gas-wanted 20000000   -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 moul
```

Keys: `mygnoscan.url` (base URL) and `mygnoscan.network` (overrides the
`?network=` id, for an instance that names the chain differently; normally
unset, and the chain-id decides). Unset, readers fall back to
[`p/moul/mygnoscan`](../../../p/moul/mygnoscan)'s `DefaultBase`, so a realm
importing this one still renders correctly on a chain where nothing was ever
configured.

`MygnoscanFor` takes the path explicitly and there is no zero-argument version.
`p/moul/mygnoscan` *can* name the calling realm by stack-walking, but the stack
seen from inside this realm has this realm on it, so such a helper would
confidently return `gno.land/r/moul/config` for every caller.

## Managers

```go
func AddManager(cur realm, addr address) error
func RemoveManager(cur realm, addr address) error
func TransferManagement(cur realm, newAuthority authz.Authority) error
func ListManagers(cur realm) []address
func HasManager(cur realm, addr address) bool
```

A thin layer over [`p/moul/authz`](../../../p/moul/authz). `init` refuses to
run unless the caller is an EOA (`cur.Previous().IsUserCall()`) and seeds the
authority with that address; that address is then the only one that can write a
setting until it adds another.

`AddManager` and `RemoveManager` only work while the authority is a
`MemberAuthority`. Once `TransferManagement` hands control to something else (a
DAO, a contract), they return an error rather than silently bypassing the new
authority, and `Set` follows the new authority from that moment on: it asks the
`Authorizer`, not a member list.

The realm governs itself. There is no address hardcoded in the settings path,
so handing this realm to a DAO hands it the settings too.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/config/v1 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/config/v1/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
