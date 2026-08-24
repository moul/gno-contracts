// Package ratelimitdemo is a small on-chain demo of the token-bucket rate
// limiter provided by the [p/moul/x/daily/ratelimit](/p/moul/x/daily/ratelimit/v1)
// library.
//
// It holds a single package-level [ratelimit.Limiter] and wires it to the
// chain: the tick is runtime.ChainHeight() and each caller is keyed by its
// address (unsafe.PreviousRealm().Address()). It contains no limiter logic of
// its own — refill/consume math all lives in the library.
package ratelimitdemo

import (
	"strconv"

	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/x/daily/ratelimit/v1"
)

// limiter starts at 0.5 tokens/block (one every two blocks), capacity 5.
var limiter = ratelimit.New(0.5, 5.0)

// Allow consumes one token for the calling realm/user at the current block
// height and reports whether the request is permitted. Returns false (and
// consumes nothing) when the caller's bucket is empty.
func Allow(cur realm) bool {
	addr := unsafe.PreviousRealm().Address()
	return limiter.Allow(string(addr), runtime.ChainHeight())
}

// SetConfig updates the shared rate (tokens per block) and burst (capacity).
// rate is clamped to >= 0, burst to >= 1.
func SetConfig(cur realm, rate, burst float64) {
	limiter.SetConfig(rate, burst)
}

// Tokens reports how many whole tokens `addr` has available at the current
// block height, without mutating any state.
func Tokens(addr address) int {
	return limiter.Tokens(string(addr), runtime.ChainHeight())
}

// --- rendering --------------------------------------------------------------

func ftoa(f float64) string { return strconv.FormatFloat(f, 'g', -1, 64) }

// Render shows the limiter config and a table of known callers with their
// current tokens and last-seen height. Path "/addr/<address>" focuses one
// caller.
func Render(path string) string {
	now := runtime.ChainHeight()
	rate, burst := limiter.Config()

	if len(path) > 6 && path[:6] == "/addr/" {
		key := path[6:]
		out := "# Rate Limiter — caller\n\n"
		out += "Address: `" + key + "`\n\n"
		out += "- Current tokens: **" + strconv.Itoa(limiter.Tokens(key, now)) + "** / " + ftoa(burst) + "\n"
		out += "- Now (height): " + strconv.FormatInt(now, 10) + "\n"
		return out
	}

	out := "# Rate Limiter\n\n"
	out += "Demo of the [`p/moul/x/daily/ratelimit`](/p/moul/x/daily/ratelimit/v1) library — "
	out += "an on-chain token-bucket limiter (port of `golang.org/x/time/rate`).\n\n"
	out += "## Config\n\n"
	out += "| Parameter | Value |\n|---|---|\n"
	out += "| Rate (tokens/block) | " + ftoa(rate) + " |\n"
	out += "| Burst (capacity) | " + ftoa(burst) + " |\n"
	out += "| Clock height | " + strconv.FormatInt(now, 10) + " |\n\n"

	out += "## Callers\n\n"
	if limiter.Len() == 0 {
		out += "_No caller has hit the limiter yet._\n\n"
	} else {
		out += "| Address | Tokens | Last height |\n|---|---|---|\n"
		limiter.Iterate(now, func(key string, tokens int, last int64) bool {
			out += "| `" + key + "` | " + strconv.Itoa(tokens) +
				" | " + strconv.FormatInt(last, 10) + " |\n"
			return false
		})
		out += "\n"
	}

	out += "---\n"
	out += "Call `Allow(cur)` to consume a token; read `Tokens(addr)` for a caller's balance.\n"
	return out
}
