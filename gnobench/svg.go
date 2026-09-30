package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
)

// Charts for the README.
//
// GitHub renders markdown, not JavaScript, so the dashboard's SVG cannot go in
// a README. These are plain static SVG files with no script and no external
// font, which is what GitHub's sanitiser leaves intact, and they are written in
// a light and a dark variant so a `<picture>` can pick one: a single chart
// tuned for one background is unreadable on the other for half the readers.
//
// One series per chart, sorted, every bar directly labelled. There are more
// candidates than there are colour-blind-safe hues, so identity is carried by
// position and by the label, never by colour.

type svgTheme struct {
	name     string
	surface  string
	ink      string
	ink2     string
	muted    string
	axis     string
	series   string
	gridline string
}

var svgThemes = []svgTheme{
	{"light", "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#c3c2b7", "#2a78d6", "#e1e0d9"},
	{"dark", "#1a1a19", "#ffffff", "#c3c2b7", "#898781", "#383835", "#3987e5", "#2c2c2a"},
}

type bar struct {
	Label string
	Value float64
	Note  string
}

// wrapText breaks on spaces at a column budget. Crude, and enough: these are
// one-sentence captions, not paragraphs.
func wrapText(s string, cols int) []string {
	words := strings.Fields(s)
	if len(words) == 0 {
		return nil
	}
	var out []string
	line := words[0]
	for _, w := range words[1:] {
		if len(line)+1+len(w) > cols {
			out = append(out, line)
			line = w
			continue
		}
		line += " " + w
	}
	return append(out, line)
}

func esc(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")
	return r.Replace(s)
}

// barChartSVG renders one horizontal bar chart. Width is fixed so the two
// theme variants line up pixel for pixel inside a <picture>.
func barChartSVG(t svgTheme, title, caption string, bars []bar) string {
	const (
		w      = 860
		padL   = 268
		padR   = 96
		titleH = 26
		capH   = 14
		rowH   = 26
		barH   = 13
		footH  = 26
		// Roughly how many characters of the 11px caption fit across the
		// canvas. SVG has no text wrapping, so the caption is wrapped here
		// or it runs off the edge.
		capCols = 148
	)
	capLines := wrapText(caption, capCols)
	_ = capLines
	headH := titleH + len(capLines)*capH + 6
	h := headH + len(bars)*rowH + footH
	maxV := 0.0
	for _, b := range bars {
		if b.Value > maxV {
			maxV = b.Value
		}
	}
	if maxV <= 0 {
		maxV = 1
	}
	plotW := float64(w - padL - padR)

	// A bar encodes magnitude by length, which means it has to start at
	// zero, which means a range this wide leaves the small values invisible.
	// Past 50x between the smallest and the largest, switch to a dot on a
	// logarithmic axis: a dot encodes position, not length, so a log scale
	// is honest there in a way it never is on a bar.
	minV := bars[0].Value
	for _, b := range bars {
		if b.Value > 0 && b.Value < minV {
			minV = b.Value
		}
	}
	logMode := minV > 0 && maxV/minV > 50
	if logMode {
		caption += " Logarithmic scale, so each gridline is 10x the one before it."
		capLines = wrapText(caption, capCols)
		headH = titleH + len(capLines)*capH + 6
		h = headH + len(bars)*rowH + footH
	}

	var s strings.Builder
	fmt.Fprintf(&s, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="%s">`,
		w, h, w, h, esc(title))
	fmt.Fprintf(&s, `<rect width="%d" height="%d" rx="8" fill="%s"/>`, w, h, t.surface)
	fmt.Fprintf(&s, `<style>text{font-family:system-ui,-apple-system,"Segoe UI",Helvetica,Arial,sans-serif}</style>`)
	fmt.Fprintf(&s, `<text x="16" y="20" font-size="14" font-weight="600" fill="%s">%s</text>`,
		t.ink, esc(title))
	for i, ln := range capLines {
		fmt.Fprintf(&s, `<text x="16" y="%d" font-size="11" fill="%s">%s</text>`,
			titleH+12+i*capH, t.muted, esc(ln))
	}

	// Log axis decades, drawn behind the marks.
	if logMode {
		lo, hi := math.Floor(math.Log10(minV)), math.Ceil(math.Log10(maxV))
		for d := lo; d <= hi; d++ {
			x := float64(padL) + (d-lo)/(hi-lo)*plotW
			fmt.Fprintf(&s, `<line x1="%.1f" x2="%.1f" y1="%d" y2="%.1f" stroke="%s" stroke-width="1"/>`,
				x, x, headH, float64(headH+len(bars)*rowH), t.gridline)
		}
	}

	pos := func(v float64) float64 {
		if !logMode {
			return v / maxV * plotW
		}
		lo, hi := math.Floor(math.Log10(minV)), math.Ceil(math.Log10(maxV))
		if v <= 0 {
			return 0
		}
		return (math.Log10(v) - lo) / (hi - lo) * plotW
	}

	for i, b := range bars {
		y := float64(headH + i*rowH)
		bw := pos(b.Value)
		if bw < 1 {
			bw = 1
		}
		if logMode {
			fmt.Fprintf(&s, `<circle cx="%.1f" cy="%.1f" r="5" fill="%s" stroke="%s" stroke-width="2"/>`,
				float64(padL)+bw, y+float64(rowH)/2, t.series, t.surface)
		} else {
			fmt.Fprintf(&s, `<rect x="%d" y="%.1f" width="%.1f" height="%d" rx="4" fill="%s"/>`,
				padL, y+float64(rowH-barH)/2, bw, barH, t.series)
		}
		fmt.Fprintf(&s, `<text x="%d" y="%.1f" font-size="12" text-anchor="end" fill="%s">%s</text>`,
			padL-10, y+float64(rowH+barH)/2-2, t.ink, esc(b.Label))
		lab := fmtN(b.Value)
		if b.Note != "" {
			lab += " " + b.Note
		}
		lx := float64(padL) + bw + 6
		anchor := "start"
		// On a log axis the rightmost mark sits at the edge, so its label
		// goes to its left instead of off the canvas.
		if lx+float64(len(lab))*6 > float64(w-4) {
			lx = float64(padL) + bw - 10
			anchor = "end"
		}
		fmt.Fprintf(&s, `<text x="%.1f" y="%.1f" font-size="11" text-anchor="%s" fill="%s">%s</text>`,
			lx, y+float64(rowH+barH)/2-2, anchor, t.ink2, esc(lab))
	}
	fmt.Fprintf(&s, `<line x1="%d" x2="%d" y1="%d" y2="%.1f" stroke="%s" stroke-width="1"/>`,
		padL, padL, headH, float64(headH+len(bars)*rowH), t.axis)
	fmt.Fprintf(&s, `<text x="%d" y="%d" font-size="11" fill="%s">lower is better</text>`,
		padL, h-9, t.muted)
	s.WriteString(`</svg>`)
	return s.String()
}

// writeCharts writes every chart a suite offers, in both themes, and returns
// the base names it wrote so the README can reference them.
func writeCharts(root string, s *Suite, files []*File) ([]chartRef, error) {
	if len(files) == 0 {
		return nil, nil
	}
	v := newView(files[0])
	specs := chartSpecs(s, v)
	dir := filepath.Join(root, "reports")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	var out []chartRef
	for _, sp := range specs {
		if len(sp.bars) == 0 {
			continue
		}
		for _, th := range svgThemes {
			name := fmt.Sprintf("%s-%s-%s.svg", s.Name, sp.slug, th.name)
			body := barChartSVG(th, sp.title, sp.caption, sp.bars)
			if err := os.WriteFile(filepath.Join(dir, name), []byte(body+"\n"), 0o644); err != nil {
				return nil, err
			}
		}
		out = append(out, chartRef{Slug: sp.slug, Title: sp.title, Suite: s.Name, Anchor: sp.anchor})
	}
	return out, nil
}

type chartRef struct {
	Slug   string
	Title  string
	Suite  string
	Anchor string
}

type chartSpec struct {
	slug    string
	title   string
	caption string
	anchor  string
	bars    []bar
}

// trimOutliers drops anything far above the median and says so in the caption.
// One candidate three orders of magnitude off squashes every other bar into a
// sliver, which hides the comparison the chart exists to make. Cutting it
// silently would be worse, so the caption names what was cut and by how much.
func trimOutliers(bars []bar, caption string) ([]bar, string) {
	if len(bars) < 4 {
		return bars, caption
	}
	med := bars[len(bars)/2].Value
	if med <= 0 {
		return bars, caption
	}
	var kept []bar
	var cut []string
	for _, b := range bars {
		if b.Value > med*8 {
			cut = append(cut, fmt.Sprintf("%s at %s", b.Label, fmtN(b.Value)))
			continue
		}
		kept = append(kept, b)
	}
	if len(cut) == 0 || len(kept) < 2 {
		return bars, caption
	}
	return kept, caption + ". Off the scale, cut so the rest is readable: " + strings.Join(cut, ", ") + "."
}

// chartSpecs picks what is worth a picture. Two for a suite that persists
// things (what one transaction costs, and what one entry costs to keep), one
// for a suite that does not.
func chartSpecs(s *Suite, v view) []chartSpec {
	sizes := v.sizes()
	if len(sizes) == 0 {
		return nil
	}
	big := sizes[len(sizes)-1]

	var specs []chartSpec
	// 1. one cold transaction, one read.
	if bars := collect(s, v, "kv", "str", "cold", "tx_read", big, ""); len(bars) > 0 {
		cap := "what a realm pays per call: the container was committed by an earlier transaction and this one touches it once"
		bars, cap = trimOutliers(bars, cap)
		specs = append(specs, chartSpec{
			slug:    "tx-read",
			title:   fmt.Sprintf("Gas for ONE read, cold, against %s entries", addCommas(itoa(big))),
			caption: cap,
			anchor:  "one-transaction-one-operation",
			bars:    bars,
		})
	}
	// 2. storage per entry.
	if bars := collectBytes(s, v, "str", big, ""); len(bars) > 0 {
		cap := "keyed and positional containers together, so read the labels: at storage_price 100 ugnot/byte this is the deposit, locked until something frees it"
		bars, cap = trimOutliers(bars, cap)
		specs = append(specs, chartSpec{
			slug:    "bytes",
			title:   fmt.Sprintf("Bytes of realm state per entry, at %s entries", addCommas(itoa(big))),
			caption: cap,
			anchor:  "storage-per-entry",
			bars:    bars,
		})
	}
	// 3. the wiring suite: what the node is actually asked to write.
	if s.Name == "wiring" {
		var bars []bar
		for _, c := range wiringCandidates {
			many, ok := v.get(c.Name, "str", "cold", shapePerTx, big)
			one, ok2 := v.get(c.Name, "str", "cold", shapeOneTx, big)
			if !ok || !ok2 || one.KVSetBytes == 0 {
				continue
			}
			bars = append(bars, bar{
				Label: c.Name, Value: float64(many.KVSetBytes),
				Note: fmt.Sprintf("(%.0fx the batched write)", float64(many.KVSetBytes)/float64(one.KVSetBytes)),
			})
		}
		sortBars(bars)
		if len(bars) > 0 {
			cap := fmt.Sprintf("%s writes arriving one transaction at a time. Every one of these ends at the same state and is charged the same deposit.",
				addCommas(itoa(big)))
			bars, cap = trimOutliers(bars, cap)
			specs = append(specs, chartSpec{
				slug:    "kv-bytes",
				title:   "Bytes the key/value store is asked to write",
				caption: cap,
				anchor:  "batched-against-one-at-a-time",
				bars:    bars,
			})
		}
		return specs
	}

	// 4. pure computation: gas per call at the largest input.
	if bars := collect(s, v, "digest", "str", "warm", "x64", big, "gas"); len(bars) > 0 {
		cap := "amortised over 64 calls, so the input build is subtracted out"
		bars, cap = trimOutliers(bars, cap)
		specs = append(specs, chartSpec{
			slug:    "per-call",
			title:   fmt.Sprintf("Gas per call on %s %s-byte input", article(big), addCommas(itoa(big))),
			caption: cap,
			anchor:  "every-workload",
			bars:    bars,
		})
	}
	return specs
}

func collect(s *Suite, v view, group, value, mode, workload string, n int, _ string) []bar {
	var out []bar
	for _, st := range s.Structures {
		if st.Group != group || !st.takesValue(value) {
			continue
		}
		r, ok := v.get(st.Name, value, mode, workload, n)
		if !ok || r.Ops == 0 {
			continue
		}
		out = append(out, bar{Label: st.Name, Value: float64(r.DGas) / float64(r.Ops)})
	}
	sortBars(out)
	return out
}

// article picks "a" or "an" for a number read aloud: "an 8,192-byte input",
// "a 1,024-byte input". Wrong here is small but it is the front page.
func article(n int) string {
	s := itoa(n)
	switch s[0] {
	case '8':
		return "an"
	case '1':
		if len(s) == 2 || (len(s) > 2 && (s[1] == '1' || s[1] == '8')) {
			return "an"
		}
	}
	return "a"
}

// collectBytes gathers storage per entry. group narrows it; empty means every
// container, keyed and positional alike.
func collectBytes(s *Suite, v view, value string, n int, group string) []bar {
	var out []bar
	for _, st := range s.Structures {
		if !st.takesValue(value) {
			continue
		}
		if group != "" && st.Group != group {
			continue
		}
		wl := "insert_rand"
		if st.Group == "list" {
			wl = "append_n"
		}
		r, ok := v.get(st.Name, value, "warm", wl, n)
		if !ok || r.Ops == 0 {
			continue
		}
		per := float64(r.DBytes) / float64(r.Ops)
		out = append(out, bar{
			Label: st.Name, Value: per,
			Note: "(" + fmtN(per*100000*100/1e6) + " GNOT / 100k)",
		})
	}
	sortBars(out)
	return out
}

func sortBars(b []bar) {
	for i := 1; i < len(b); i++ {
		for j := i; j > 0 && b[j].Value < b[j-1].Value; j-- {
			b[j], b[j-1] = b[j-1], b[j]
		}
	}
}
