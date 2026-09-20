package collatz

import (
	"chain"
	"chain/runtime/unsafe"
	"sort"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// maxIters caps the Collatz walk so a hostile / huge input cannot loop
// forever on-chain. No known n stays below this bound and fails to reach 1.
const maxIters = 1000000

// maxSeqLen caps how many terms Render("/<n>") will print.
const maxSeqLen = 500

// Result is one recorded submission.
type Result struct {
	N     int64
	Steps int
	Peak  int64
	Who   address
}

// results maps a decimal-string key of N -> Result. avl.Tree keeps a
// deterministic order for iteration inside Render.
var results avl.Tree

// stopping returns the number of steps to reach 1 and the peak value seen,
// walking the Collatz (hailstone) map. It never mutates state.
func stopping(n int64) (steps int, peak int64) {
	peak = n
	cur := n
	for cur != 1 {
		if steps >= maxIters {
			break
		}
		if cur%2 == 0 {
			cur = cur / 2
		} else {
			cur = 3*cur + 1
		}
		if cur > peak {
			peak = cur
		}
		steps++
	}
	return steps, peak
}

// Compute walks the hailstone sequence for n and records the result
// attributed to the caller. It is a crossing (state-mutating) func.
func Compute(cur realm, n int) {
	if n <= 0 {
		panic("n must be > 0")
	}
	caller := unsafe.PreviousRealm().Address()
	nn := int64(n)
	steps, peak := stopping(nn)

	res := Result{N: nn, Steps: steps, Peak: peak, Who: caller}
	key := strconv.FormatInt(nn, 10)
	results.Set(key, res)

	chain.Emit(
		"Computed",
		"n", key,
		"steps", strconv.Itoa(steps),
		"peak", strconv.FormatInt(peak, 10),
		"who", caller.String(),
	)
}

// byLongest implements sort.Interface, ordering results by steps desc,
// then peak desc, then n asc for stability.
type byLongest []Result

func (b byLongest) Len() int      { return len(b) }
func (b byLongest) Swap(i, j int) { b[i], b[j] = b[j], b[i] }
func (b byLongest) Less(i, j int) bool {
	if b[i].Steps != b[j].Steps {
		return b[i].Steps > b[j].Steps
	}
	if b[i].Peak != b[j].Peak {
		return b[i].Peak > b[j].Peak
	}
	return b[i].N < b[j].N
}

// Render shows the leaderboard at root, or the full hailstone sequence for a
// given n at path "/<n>".
func Render(path string) string {
	p := strings.TrimPrefix(path, "/")
	if p == "" {
		return renderLeaderboard()
	}
	return renderSequence(p)
}

func renderLeaderboard() string {
	all := make([]Result, 0, results.Size())
	results.Iterate("", "", func(_ string, v interface{}) bool {
		all = append(all, v.(Result))
		return false
	})

	var sb strings.Builder
	sb.WriteString("# Collatz Explorer\n\n")
	sb.WriteString("Hailstone-sequence explorer. Call `Compute(n)` to record a run, ")
	sb.WriteString("or view a full sequence at `/<n>`.\n\n")

	if len(all) == 0 {
		sb.WriteString("_No sequences submitted yet._\n")
		return sb.String()
	}

	sort.Stable(byLongest(all))

	sb.WriteString("## Leaderboard — longest sequences\n\n")
	sb.WriteString("| # | n | steps | peak | who |\n")
	sb.WriteString("|---|---|-------|------|-----|\n")
	limit := len(all)
	if limit > 20 {
		limit = 20
	}
	for i := 0; i < limit; i++ {
		r := all[i]
		sb.WriteString("| " + strconv.Itoa(i+1) + " | ")
		sb.WriteString("[" + strconv.FormatInt(r.N, 10) + "](/r:" + strconv.FormatInt(r.N, 10) + ") | ")
		sb.WriteString(strconv.Itoa(r.Steps) + " | ")
		sb.WriteString(strconv.FormatInt(r.Peak, 10) + " | ")
		sb.WriteString(r.Who.String() + " |\n")
	}
	sb.WriteString("\n_" + strconv.Itoa(len(all)) + " sequence(s) recorded._\n")
	return sb.String()
}

func renderSequence(p string) string {
	n, err := strconv.ParseInt(p, 10, 64)
	var sb strings.Builder
	if err != nil || n <= 0 {
		sb.WriteString("# Invalid n\n\n`" + p + "` is not a positive integer.\n")
		return sb.String()
	}

	sb.WriteString("# Hailstone sequence for " + strconv.FormatInt(n, 10) + "\n\n")

	seq := make([]int64, 0, 64)
	cur := n
	var peak int64 = n
	truncated := false
	for {
		seq = append(seq, cur)
		if cur == 1 {
			break
		}
		if len(seq) >= maxSeqLen {
			truncated = true
			break
		}
		if cur%2 == 0 {
			cur = cur / 2
		} else {
			cur = 3*cur + 1
		}
		if cur > peak {
			peak = cur
		}
	}

	parts := make([]string, len(seq))
	for i, v := range seq {
		parts[i] = strconv.FormatInt(v, 10)
	}
	sb.WriteString(strings.Join(parts, " → "))
	sb.WriteString("\n\n")
	sb.WriteString("- steps: " + strconv.Itoa(len(seq)-1) + "\n")
	sb.WriteString("- peak: " + strconv.FormatInt(peak, 10) + "\n")
	if truncated {
		sb.WriteString("\n_Sequence truncated at " + strconv.Itoa(maxSeqLen) + " terms._\n")
	}
	return sb.String()
}
