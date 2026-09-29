package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"
)

// Env is everything about the machine and the toolchain that could move a
// number. It is recorded with every result, because a benchmark figure without
// it is not reproducible and not comparable: a result from another laptop, or
// from a different gno revision, is a different measurement of a different
// thing.
type Env struct {
	// ID is the filename these results are stored under. Same machine and
	// same OS/arch means the same file, so re-running updates rows in
	// place; a different machine writes a different file and both are kept.
	ID string `json:"id"`

	OS      string `json:"os"`
	Arch    string `json:"arch"`
	CPU     string `json:"cpu"`
	CPUs    int    `json:"cpus"`
	MemGB   int    `json:"mem_gb,omitempty"`
	Host    string `json:"host,omitempty"`
	GoVer   string `json:"go_version"`
	ToolVer string `json:"gnobench_commit,omitempty"`

	// The gno revision the numbers were produced against. A change here
	// invalidates comparison far more often than a change of machine does.
	GnoCommit string `json:"gno_commit,omitempty"`
	GnoDate   string `json:"gno_commit_date,omitempty"`
	GnoDirty  bool   `json:"gno_dirty,omitempty"`
	GnoRoot   string `json:"-"`
}

var nonID = regexp.MustCompile(`[^a-z0-9]+`)

func slug(s string) string {
	return strings.Trim(nonID.ReplaceAllString(strings.ToLower(s), "-"), "-")
}

func cmdOut(dir, name string, args ...string) string {
	c := exec.Command(name, args...)
	c.Dir = dir
	b, err := c.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// DetectEnv reads what it can and leaves the rest empty rather than guessing.
// Nothing here fails the run: a missing CPU model costs a label, not a result.
func DetectEnv(gnoroot string) Env {
	e := Env{
		OS:      runtime.GOOS,
		Arch:    runtime.GOARCH,
		CPUs:    runtime.NumCPU(),
		GoVer:   runtime.Version(),
		GnoRoot: gnoroot,
	}
	if h, err := os.Hostname(); err == nil {
		e.Host = strings.SplitN(h, ".", 2)[0]
	}
	switch runtime.GOOS {
	case "darwin":
		e.CPU = cmdOut("", "sysctl", "-n", "machdep.cpu.brand_string")
		if b := cmdOut("", "sysctl", "-n", "hw.memsize"); b != "" {
			var n int64
			fmt.Sscan(b, &n)
			e.MemGB = int(n / (1 << 30))
		}
	case "linux":
		if b, err := os.ReadFile("/proc/cpuinfo"); err == nil {
			for _, ln := range strings.Split(string(b), "\n") {
				if strings.HasPrefix(ln, "model name") {
					if i := strings.Index(ln, ":"); i >= 0 {
						e.CPU = strings.TrimSpace(ln[i+1:])
					}
					break
				}
			}
		}
	}
	if gnoroot != "" {
		e.GnoCommit = cmdOut(gnoroot, "git", "rev-parse", "HEAD")
		e.GnoDate = cmdOut(gnoroot, "git", "show", "-s", "--format=%cs", "HEAD")
		e.GnoDirty = cmdOut(gnoroot, "git", "status", "--porcelain") != ""
	}
	e.ToolVer = cmdOut("", "git", "rev-parse", "--short", "HEAD")

	cpu := e.CPU
	if cpu == "" {
		cpu = "unknown-cpu"
	}
	e.ID = fmt.Sprintf("%s-%s-%s-%dc", e.OS, e.Arch, slug(cpu), e.CPUs)
	if len(e.ID) > 80 {
		sum := sha256.Sum256([]byte(e.ID))
		e.ID = e.ID[:64] + "-" + hex.EncodeToString(sum[:3])
	}
	return e
}

// Short is the one-line form a report header uses.
func (e Env) Short() string {
	s := fmt.Sprintf("%s/%s, %s, %d cores", e.OS, e.Arch, e.CPU, e.CPUs)
	if e.MemGB > 0 {
		s += fmt.Sprintf(", %d GB", e.MemGB)
	}
	return s
}

func (e Env) GnoShort() string {
	if e.GnoCommit == "" {
		return "unknown"
	}
	s := e.GnoCommit
	if len(s) > 9 {
		s = s[:9]
	}
	if e.GnoDate != "" {
		s += " (" + e.GnoDate + ")"
	}
	if e.GnoDirty {
		s += " DIRTY"
	}
	return s
}

func nowUTC() string { return time.Now().UTC().Format(time.RFC3339) }

func mustJSON(v any) []byte {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		panic(err)
	}
	return append(b, '\n')
}
