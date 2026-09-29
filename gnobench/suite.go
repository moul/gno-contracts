package main

// A Suite is one themed benchmark: a set of candidates measured against a set
// of workloads. "storage" is the first; the shape is deliberately generic so a
// second theme is a new file, not a new tool.
type Suite struct {
	Name       string
	Title      string
	Blurb      string
	Structures []Structure
	Workloads  []Workload
	// Facets are the filter axes a report offers, in display order. Each
	// maps a tag prefix to a human label.
	Facets []Facet
	// Template is the gno file every measurement in this suite is rendered
	// into. Empty means the storage template. A suite that measures pure
	// computation has no containers and no build phase, so it needs its own.
	Template string
	// Sizes is what n means here, for the report's axis label.
	SizeLabel string
	// Unit is what one "op" is, for the per-op column.
	OpLabel string
}

type Facet struct {
	Key    string   // tag prefix, e.g. "keys"
	Label  string   // "Key type"
	Values []string // tag suffixes in display order
}

// A Structure is one candidate. Name is the import path, always, so a reader
// can tell a library apart from a language builtin without knowing the
// ecosystem: "p/nt/avl/v0" is a package someone wrote and can change,
// "builtin map[string]T" is the language.
type Structure struct {
	Name    string
	Group   string // "kv" or "list"
	Note    string
	Tags    []string
	Imports []string
	// Decl declares the container empty. The build loop never lives here:
	// where it runs is what separates a warm measurement from a cold one.
	Decl string
	Ops  string
	Skip map[string]string
	// Values restricts the value shapes this container accepts.
	Values []string
	// MaxN is a declared capacity ceiling. A candidate that refuses writes
	// past a documented cap is not failing, it is doing what it says; the
	// report records the ceiling instead of an error.
	MaxN int
	// MaxNWhy explains the ceiling, and is what the report prints.
	MaxNWhy string
}

func (s Structure) takesValue(v string) bool {
	if len(s.Values) == 0 {
		return true
	}
	for _, have := range s.Values {
		if have == v {
			return true
		}
	}
	return false
}

func (s Structure) hasTag(t string) bool {
	for _, have := range s.Tags {
		if have == t {
			return true
		}
	}
	return false
}

// A Workload is one measured phase.
//
// Mode is the whole point of this version of the tool:
//
//   - "warm": the container is built and then measured inside one run, so
//     every object it touches is already live in the VM's per-transaction
//     object cache. This is what a benchmark measures by accident.
//   - "cold": the container is built during package initialisation, which the
//     filetest runner commits and then discards the object cache for
//     ("mimicking on-chain behaviour", gnovm/pkg/test/filetest.go). Every
//     object the measured phase touches is deserialised from the store, which
//     is what a real transaction against a deployed realm does.
//
// Light skips building the key and permutation slices in main. A
// single-operation transaction does not need 10,000 keys, and at that size
// building them would cost more gas than the operation being measured.
type Workload struct {
	Name  string
	Group string
	Mode  string
	Light bool
	// Prebuilt means the container is already full when the measured body
	// runs. In warm mode the build happens in main just before it; in cold
	// mode it happens in package init, one commit earlier.
	Prebuilt bool
	Note     string
	Baseline string
	Body     string
	Ops      func(n int) int
}

func (w Workload) mode() string {
	if w.Mode == "" {
		return "warm"
	}
	return w.Mode
}

// Groups are the candidate families in this suite, in declaration order. A
// suite with one family ("digest") is as valid as one with two ("kv", "list"),
// and the report asks the suite rather than assuming.
func (s *Suite) Groups() []string {
	var out []string
	seen := map[string]bool{}
	for _, st := range s.Structures {
		if !seen[st.Group] {
			seen[st.Group] = true
			out = append(out, st.Group)
		}
	}
	return out
}

func (s *Suite) sizeLabel() string {
	if s.SizeLabel == "" {
		return "entries"
	}
	return s.SizeLabel
}

var suites = map[string]*Suite{}

func register(s *Suite) { suites[s.Name] = s }
