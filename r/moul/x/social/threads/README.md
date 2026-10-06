# `gno.land/r/moul/x/social/threads/v0`

**A discussion block any realm can embed**, keyed on the page it appears on
rather than on the realm that stores it. Two lines in the host realm, which
stores nothing:

```go
import "gno.land/r/moul/x/social/threads/v0"

func Render(path string) string {
	return body + threads.RenderBlock()
}
```

`RenderBlock` takes no argument because it does not need one. A plain read
exported by a realm and called by another opens no realm frame, so
`unsafe.CurrentRealm()` inside it reports the **caller**: the host realm's own
path is the page key, and nothing has to be configured, registered or passed.
`RenderBlockFor(page)` is the explicit form, for a realm that renders several
pages or already holds its path as a constant. Adding a `cur realm` parameter to
either would silently reverse that and key every embed to this realm.

It is the text half of
[`r/moul/reactions`](https://github.com/moul/gno-contracts/tree/main/r/moul/reactions):
the same embed shape, the same page keys, and the same reason for existing.

## The token, and the three things it has to answer

THREAD is a GRC20 issued through
[`p/moul/x/social/coin`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/social/coin),
which refuses to create a token until all three of these are written down:

| | |
|---|---|
| **mint** | 1 THREAD to a thread's author, the first time each distinct address replies to it. People, not messages, and never yourself. |
| **sink** | `Boost` burns 10 THREAD to pin a thread to the top of its page for 1,000 blocks. It is the only thing that removes supply, and the only thing the token does. |
| **buyer** | anyone who wants placement and has not earned it. They have to acquire THREAD from somebody who did, with `Transfer`. |

**Placement is the one thing a discussion has that people want and cannot all
have at once**, which is what makes it a sink worth paying for rather than a
leaderboard. A pin extends from whichever is later, now or the current pin, so
buying one never shortens somebody else's, and `Boost` charges before it pins.

**It is farmable, and saying so is cheaper than pretending otherwise**: two
addresses replying to each other mint one THREAD each per thread. The fix is a
gate on who counts as a replier, which belongs in
[`r/moul/x/social/vouch`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/social/vouch)
and not here. Until then the cost of farming is one transaction per point and
the benefit is capped by what a pin is worth.

The token is registered with `r/nt/grc20reg`, so a realm that does not import
this one can still find and move it by key: `TokenKey()` returns it.

## Why this realm is not private

Every other realm in the `x/social` family is `private = true` and can be
redeployed in place. This one cannot be, twice over: a private realm cannot be
imported at all, which would delete the embed, and handing an object to another
realm (registering the token) panics at runtime from a private realm. Every
thread, balance and pin under this path belongs to the people who wrote them, so
a fix ships as a `v1` beside it rather than as a redeploy that wipes the lot.

## Reading it

`Render("")` is the index: the counts, the recent threads across every page, the
token's three declarations, and the embed snippet. `Render("page/<page key>")`
is one page's threads, `Render("thread/<id>")` is one thread with its replies and
the reply and boost buttons.
