package smallgrants

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The page as it ships, pinned. Not an ExampleRender: an example pins the
// realm's path and address byte for byte, and the path lives on one line of
// gnomod.toml so that changing it is that line alone. The two are substituted
// in here instead.
const atDeploy = `# Small grants (demo)
> **This is a demo.** A working preview of the small-grants desk I plan to
> deploy under ` + "`gno.land/r/nt`" + ` or ` + "`gno.land/r/gnoland`" + `, once approved.
> Requests, decisions and payouts here are real; only the address is temporary.

Ask for a small amount of GNOT, for yourself or for someone else, in the open.
The controllers below decide in public: pay in full, pay a part, or refuse,
each with an optional reason. The yes that makes a majority pays the
request out of this realm's balance in the same transaction.

|  |  |
| --- | --- |
| Requests | open to everyone |
| Cap | 100 GNOT per request, and per payee over 30 days |
| Balance | **0 GNOT** |
| Paid out | 0 GNOT over 0 grant(s) |
| Decision | 2 yes of 3 controllers |
| Fund it | a plain send to ` + "`ADDR`" + ` |

## Ask
` + "```" + `
gnokey maketx call -pkgpath PATH -func Request \
  -args <payee address> -args <amount in ugnot> \
  -args '<title>' -args '<what it is for>' ...
` + "```" + `

## Open requests (0 of 30)
*Nothing is waiting for a decision.*

## Recently decided
*Nothing has been decided yet.*

## Controllers
- ` + "`g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt`" + `
- ` + "`g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6`" + `
- ` + "`g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs`" + `

## Motions
*Nobody has proposed changing the controllers.*

## Allowlist
Who may still file while the realm is paused. Its own list, not the controllers.

- ` + "`g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs`" + `
- ` + "`g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6`" + `
- ` + "`g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt`" + `
`

func TestRenderAtDeploy(t *testing.T) {
	reset()
	want := strings.NewReplacer("ADDR", Address().String(), "PATH", selfPath).Replace(atDeploy)
	uassert.Equal(t, want, Render(""))
}
