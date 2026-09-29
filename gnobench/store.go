package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// schemaVersion guards the on-disk format. Bump it when a field changes
// meaning rather than when one is added, and the reader will say so instead of
// silently mixing two definitions of the same column.
const schemaVersion = 1

// Row is one measured scenario. Every row carries the date and the gno
// revision it was measured against, so a report can warn about a row that is
// older than its neighbours instead of presenting a stale number as current.
type Row struct {
	Structure string `json:"structure"`
	Group     string `json:"group"`
	Workload  string `json:"workload"`
	Mode      string `json:"mode"`
	Value     string `json:"value"`
	N         int    `json:"n"`
	Ops       int    `json:"ops"`

	Gas    int64 `json:"gas"`
	Bytes  int64 `json:"bytes"`
	WallNs int64 `json:"wall_ns"`

	DGas    int64 `json:"d_gas"`
	DBytes  int64 `json:"d_bytes"`
	DWallNs int64 `json:"d_wall_ns"`

	Stable bool   `json:"stable"`
	Skip   string `json:"skip,omitempty"`
	Err    string `json:"err,omitempty"`

	MeasuredAt string `json:"measured_at"`
	GnoCommit  string `json:"gno_commit,omitempty"`
}

// Key identifies a scenario across runs and across machines. A re-run of the
// same scenario replaces the row with this key; a scenario nobody has run yet
// is simply absent, which is how the store stays append-friendly.
func (r Row) Key() string {
	return fmt.Sprintf("%s|%s|%s|%s|%d", r.Structure, r.Value, r.Mode, r.Workload, r.N)
}

// File is one machine's results for one suite. Two machines make two files and
// both are kept; the same machine re-running updates rows inside its own file.
type File struct {
	Schema    int            `json:"schema"`
	Suite     string         `json:"suite"`
	Env       Env            `json:"env"`
	UpdatedAt string         `json:"updated_at"`
	Rows      map[string]Row `json:"rows"`

	path string
}

func resultsPath(root, suite, envID string) string {
	return filepath.Join(root, "results", suite, envID+".json")
}

// LoadFile reads this machine's file for a suite, or returns an empty one.
func LoadFile(root, suite string, env Env) (*File, error) {
	p := resultsPath(root, suite, env.ID)
	f := &File{Schema: schemaVersion, Suite: suite, Env: env, Rows: map[string]Row{}, path: p}
	b, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return f, nil
	}
	if err != nil {
		return nil, err
	}
	var on File
	if err := json.Unmarshal(b, &on); err != nil {
		return nil, fmt.Errorf("%s: %w", p, err)
	}
	if on.Schema != schemaVersion {
		return nil, fmt.Errorf("%s: schema %d, this build writes %d; migrate or move the file aside",
			p, on.Schema, schemaVersion)
	}
	if on.Rows == nil {
		on.Rows = map[string]Row{}
	}
	on.path = p
	// The environment is refreshed on every write: the machine is the same
	// (that is what the filename means) but its go version or gno revision
	// may have moved since the last run.
	on.Env = env
	on.Suite = suite
	return &on, nil
}

// Merge folds new rows in, replacing any scenario measured before.
func (f *File) Merge(rows []Row) (added, replaced int) {
	for _, r := range rows {
		k := r.Key()
		if _, ok := f.Rows[k]; ok {
			replaced++
		} else {
			added++
		}
		f.Rows[k] = r
	}
	return
}

func (f *File) Save() error {
	f.Schema = schemaVersion
	f.UpdatedAt = nowUTC()
	if err := os.MkdirAll(filepath.Dir(f.path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(f.path, mustJSON(f), 0o644)
}

// LoadAll reads every machine's file for a suite. Report generation always
// goes through this, so adding a machine is nothing but dropping in a file.
func LoadAll(root, suite string) ([]*File, error) {
	dir := filepath.Join(root, "results", suite)
	ents, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []*File
	for _, e := range ents {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		p := filepath.Join(dir, e.Name())
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, err
		}
		var f File
		if err := json.Unmarshal(b, &f); err != nil {
			return nil, fmt.Errorf("%s: %w", p, err)
		}
		if f.Schema != schemaVersion {
			return nil, fmt.Errorf("%s: schema %d, this build reads %d", p, f.Schema, schemaVersion)
		}
		f.path = p
		out = append(out, &f)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Env.ID < out[j].Env.ID })
	return out, nil
}

// Warnings is the staleness report a generated document carries. It is
// computed, not asserted: a reader should never have to guess whether a table
// mixes measurements from two different gno revisions.
type Warnings struct {
	MixedGno   []string
	OldestDays int
	NewestDays int
	Stale      []string
	Unstable   []string
	Failed     []string
}

func (f *File) Warn(maxAgeDays int) Warnings {
	var w Warnings
	seen := map[string]int{}
	oldest, newest := time.Time{}, time.Time{}
	for _, r := range f.Rows {
		if r.GnoCommit != "" {
			seen[r.GnoCommit]++
		}
		t, err := time.Parse(time.RFC3339, r.MeasuredAt)
		if err != nil {
			continue
		}
		if oldest.IsZero() || t.Before(oldest) {
			oldest = t
		}
		if newest.IsZero() || t.After(newest) {
			newest = t
		}
		if maxAgeDays > 0 && time.Since(t) > time.Duration(maxAgeDays)*24*time.Hour {
			w.Stale = append(w.Stale, r.Key())
		}
		if r.Err != "" {
			w.Failed = append(w.Failed, r.Key()+": "+r.Err)
		} else if r.Skip == "" && !r.Stable {
			w.Unstable = append(w.Unstable, r.Key())
		}
	}
	for c, n := range seen {
		short := c
		if len(short) > 9 {
			short = short[:9]
		}
		w.MixedGno = append(w.MixedGno, fmt.Sprintf("%s (%d rows)", short, n))
	}
	sort.Strings(w.MixedGno)
	sort.Strings(w.Stale)
	sort.Strings(w.Unstable)
	sort.Strings(w.Failed)
	if !oldest.IsZero() {
		w.OldestDays = int(time.Since(oldest).Hours() / 24)
		w.NewestDays = int(time.Since(newest).Hours() / 24)
	}
	return w
}
