package main

import (
	"bytes"
	"text/template"
)

// scenarioTemplate is the single gno file every measurement runs as.
//
// The one thing to understand here is where phaseBuild is called from.
//
// Called from main, the container is built and measured inside one run, so
// every object the measured phase touches is already live in the VM's
// per-transaction object cache. That is a WARM measurement, and it is what a
// benchmark produces by accident.
//
// Called from a package-level var, it runs during package initialisation,
// which gnovm's filetest runner commits and then reconstructs the machine from
// ("Clear store cache and reconstruct machine from committed info (mimicking
// on-chain behaviour)", gnovm/pkg/test/filetest.go). main then starts with an
// empty object cache and deserialises every object it touches. That is a COLD
// measurement, and it is what a real transaction against a deployed realm
// does.
//
// The difference is not cosmetic: a container held in one persisted object is
// O(1) warm and O(n) cold, because the first touch loads all of it.
const scenarioTemplate = `// PKGPATH: gno.land/r/scratch/bench
package bench

import (
	"strconv"
{{- range .Imports}}
	{{.}}
{{- end}}
)

const n = {{.N}}

// rec is the "live object graph" value shape, the alternative to a string
// payload. Which one a scenario stores is the mechanism axis.
type rec struct {
	A string
	B int
}

{{.Decl}}

{{.Ops}}

// key returns a fixed-width key, so lexicographic order equals numeric order
// and every candidate sees keys of identical length.
func key(i int) string {
	s := strconv.Itoa(i)
	for len(s) < 8 {
		s = "0" + s
	}
	return "k" + s
}

// shuffle is a deterministic Fisher-Yates over a xorshift64 stream, so every
// candidate and every n sees the same order.
func shuffle(seed uint64, size int) []int {
	p := make([]int, size)
	for i := 0; i < size; i++ {
		p[i] = i
	}
	s := seed
	for i := size - 1; i > 0; i-- {
		s ^= s << 13
		s ^= s >> 7
		s ^= s << 17
		j := int(s % uint64(i+1))
		p[i], p[j] = p[j], p[i]
	}
	return p
}

func val(i int) any {
	return {{.ValueExpr}}
}

// phaseBuild fills the container. It takes its inputs rather than building
// them, so that a warm scenario can hand it the same slices main already has:
// then the difference between "built" and "built and then measured" is the
// measured phase and nothing else.
func phaseBuild(ks []string, pm []int) bool {
{{.BuildBody}}
	return true
}

// coldBuild is the same build with its own inputs, for the package-init path
// where main's slices do not exist yet.
func coldBuild() bool {
	ks := make([]string, n)
	for i := 0; i < n; i++ {
		ks[i] = key(i)
	}
	return phaseBuild(ks, shuffle(0x9E3779B97F4A7C15, n))
}
{{if .InitBuild}}
// Built during package init, so main runs against a committed, cold store.
var _ = coldBuild()
{{end}}
func main() {
{{- if .Light}}
	// A single-operation transaction needs one key and one value, not n of
	// them. They are hoisted here so that every tx_* workload, including the
	// baseline that does nothing with them, pays for them identically and
	// the subtraction leaves only the operation.
	k := key(n / 2)
	v := val(0)
	_, _ = k, v
{{- else}}
	ks := make([]string, n)
	for i := 0; i < n; i++ {
		ks[i] = key(i)
	}
	pm := shuffle(0x9E3779B97F4A7C15, n)
	pm2 := shuffle(0xD1B54A32D192ED03, n)
	_, _, _ = ks, pm, pm2
{{- end}}
{{- if .MainBuild}}
	phaseBuild(ks, pm)
{{- end}}

{{.Body}}
	println("done")
}

// Output:
// done
`

type scenarioData struct {
	Imports   []string
	Decl      string
	Ops       string
	ValueExpr string
	BuildBody string
	Body      string
	N         int
	InitBuild bool
	MainBuild bool
	Light     bool
}

var tmplCache = map[string]*template.Template{}

func render(src string, d scenarioData) ([]byte, error) {
	if src == "" {
		src = scenarioTemplate
	}
	t, ok := tmplCache[src]
	if !ok {
		var err error
		t, err = template.New("scenario").Parse(src)
		if err != nil {
			return nil, err
		}
		tmplCache[src] = t
	}
	var buf bytes.Buffer
	if err := t.Execute(&buf, d); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
