package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// The deploy plan. gnopm manages versions and the lock, not publishing, and
// tools/gnopublish signs transactions itself rather than emitting them. Neither
// answers "tell me what is missing, size it, and hand me commands I can read
// before anything is signed", which is the only shape that works when the key
// is moul's master key and the agent may not touch it.
//
// Everything here is read-only. The output is text for a human to review and
// paste, exactly like `tx`.

// uploadedExtensions mirrors goodFileXtns in the gno toolchain
// (gnovm/pkg/gnolang/mempackage.go). `gnokey maketx addpkg` reads the package
// directory with MPUserAll (gno.land/pkg/keyscli/addpkg.go), so test files and
// the README travel too, and they are what the gas and the storage deposit are
// charged on. Sub-directories are skipped, which is why content/ never ships.
var uploadedExtensions = []string{".gno", ".toml", ".md"}

// gasPerByteWorstCase is the top of the range measured over ten successful
// mainnet add_package transactions above h160000 on 2026-09-19: 1,014 to 1,781
// gas per uploaded byte, median 1,393. The spread is the package's own init()
// work, which the byte count cannot see, so size from the top. gas-wanted is a
// ceiling and a ceiling is not charged.
const gasPerByteWorstCase = 1800

// feeRatioMicro is the gas fee offered per unit of gas, in millionths of a
// ugnot: 10_000 = 0.01 ugnot/gas. The lowest ratio accepted on mainnet is
// 0.001, so this is ten times the floor, which survives an upward drift in the
// block gas price for a rounding error.
//
// The ratio matters and the absolute does not: EnsureSufficientMempoolFees
// compares fee/gas_wanted, so raising the ceiling raises the required fee.
// And gas_fee is deducted in full as offered and never refunded, unlike
// max_deposit, so over-offering is a real cost rather than insurance. The flat
// 1000000ugnot this tool used to emit was 92 times the floor on a slot write.
const feeRatioMicro = 10_000

// feeFor sizes the gas fee from the ceiling it accompanies, never below 1ugnot.
func feeFor(gasWanted int64) string {
	fee := gasWanted * feeRatioMicro / 1_000_000
	if fee < 1 {
		fee = 1
	}
	return strconv.FormatInt(fee, 10) + "ugnot"
}

// uploadFile is one file of the MsgAddPackage payload.
type uploadFile struct {
	name string
	size int
}

// payload lists what `addpkg -pkgdir <dir>` would actually upload, and the
// byte count gas and storage are charged on: file bodies plus their names, the
// same total the message carries.
func payload(dir string) ([]uploadFile, int, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, 0, err
	}
	var files []uploadFile
	total := 0
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || strings.HasPrefix(name, ".") {
			continue
		}
		ok := false
		for _, x := range uploadedExtensions {
			if strings.HasSuffix(name, x) {
				ok = true
				break
			}
		}
		if !ok {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, 0, err
		}
		files = append(files, uploadFile{name: name, size: int(info.Size())})
		total += int(info.Size()) + len(name)
	}
	sort.Slice(files, func(i, j int) bool { return files[i].size > files[j].size })
	return files, total, nil
}

// productionImports returns the gno.land packages the realm imports from its
// non-test files, which are the ones that must already be on chain. Test files
// are excluded: they travel with the package but the VM never runs them, so a
// missing test-only import does not block a deploy.
func productionImports(dir, self string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".gno") || strings.HasSuffix(name, "_test.gno") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		for _, line := range strings.Split(string(b), "\n") {
			i := strings.Index(line, `"gno.land/`)
			if i < 0 {
				continue
			}
			rest := line[i+1:]
			j := strings.IndexByte(rest, '"')
			if j < 0 {
				continue
			}
			if p := rest[:j]; p != self {
				seen[p] = true
			}
		}
	}
	out := make([]string, 0, len(seen))
	for p := range seen {
		out = append(out, p)
	}
	sort.Strings(out)
	return out, nil
}

// pkgState is what the chain says about one package path.
type pkgState string

const (
	stateLive   pkgState = "live"
	stateParked pkgState = "parked"
	stateAbsent pkgState = "absent"
)

// packageState distinguishes the three states the catalog cannot. A parked
// package answers "package not found" to every ordinary query, exactly like an
// absent one, because gnoland-1 runs code_submission_policy = "inert":
// MsgAddPackage stores the bytes under inert_pkg:<path> and returns
// success:true without making the package live. vm/qinertpaths is the only
// read that sees them.
func packageState(remote, path string, inert []string) pkgState {
	for _, p := range inert {
		if p == path {
			return stateParked
		}
	}
	if _, err := abciQuery(remote, "vm/qfile", path); err != nil {
		return stateAbsent
	}
	return stateLive
}

// inertPaths lists every package parked awaiting an approver. An error is
// reported as an empty list by the caller: a chain without the inert policy has
// no such endpoint, and that is not a deploy blocker.
func inertPaths(remote string) ([]string, error) {
	raw, err := abciQuery(remote, "vm/qinertpaths", "")
	if err != nil {
		return nil, err
	}
	var out []string
	for _, l := range strings.Split(raw, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

// printDeploy writes the preflight report and then the commands, in order.
func printDeploy(out *os.File, cfg config, pkgdir string, local []slotFile) error {
	files, total, err := payload(pkgdir)
	if err != nil {
		return err
	}
	if total == 0 {
		return fmt.Errorf("%s: nothing to upload", pkgdir)
	}

	inert, inertErr := inertPaths(cfg.remote)
	state := packageState(cfg.remote, cfg.realm, inert)

	fmt.Fprintf(out, "# %s on %s\n#\n", cfg.realm, cfg.chainID)
	fmt.Fprintf(out, "# state      %s\n", state)

	deps, err := productionImports(pkgdir, cfg.realm)
	if err != nil {
		return err
	}
	missing := 0
	for _, d := range deps {
		ds := packageState(cfg.remote, d, inert)
		if ds != stateLive {
			missing++
		}
		fmt.Fprintf(out, "# dep        %-8s %s\n", ds, d)
	}
	if inertErr != nil {
		fmt.Fprintf(out, "# note       could not read vm/qinertpaths (%v);\n"+
			"#            'absent' below cannot be told apart from 'parked'\n", inertErr)
	}

	gas := int64(total) * gasPerByteWorstCase
	fmt.Fprintf(out, "# payload    %d bytes in %d files\n", total, len(files))
	for _, f := range files {
		fmt.Fprintf(out, "#              %7d  %s\n", f.size, f.name)
	}
	fmt.Fprintf(out, "# gas        %d (worst case, %d gas/byte measured on mainnet)\n", gas, gasPerByteWorstCase)
	fmt.Fprintf(out, "# fee        %s (%s ugnot/gas, ten times the accepted floor; never refunded)\n",
		feeFor(gas), strconv.FormatFloat(float64(feeRatioMicro)/1e6, 'g', -1, 64))
	fmt.Fprintf(out, "# deposit    %s locked at 100ugnot/byte for the source alone, plus realm state\n",
		gnotStr(int64(total)*100))

	if missing > 0 {
		noun := "dependency is"
		if missing > 1 {
			noun = "dependencies are"
		}
		fmt.Fprintf(out, "#\n# STOP: %d %s not live. Publish those first.\n", missing, noun)
		return fmt.Errorf("%d %s not live on %s", missing, noun, cfg.chainID)
	}

	switch state {
	case stateLive:
		fmt.Fprintf(out, "#\n# Already live. Skip to the content commands below;\n"+
			"# re-running addpkg would need private = true and would WIPE realm state.\n")
	case stateParked:
		fmt.Fprintf(out, "#\n# Already parked, waiting on an approver in vm:p:pkg_approvers.\n"+
			"# Do not send addpkg again. Re-check with the qinertpaths line below.\n")
	}

	if state == stateAbsent {
		fmt.Fprintf(out, "\n# 1. Dry run: signs locally, asks the node for the real GasUsed,\n"+
			"#    does not broadcast. A code-bearing message cannot be simulated unsigned.\n")
		fmt.Fprint(out, addpkgCmd(cfg, pkgdir, gas, true))
		fmt.Fprintf(out, "\n# 2. Broadcast. Size -gas-wanted down from the GasUsed above if you like.\n")
		fmt.Fprint(out, addpkgCmd(cfg, pkgdir, gas, false))
	}

	if state != stateLive {
		fmt.Fprintf(out, "\n# 3. It is PARKED, not live, until an approver enables it.\n"+
			"#    Listed means still parked; gone means live.\n")
		fmt.Fprintf(out, "curl -s '%s/abci_query?path=%%22vm%%2Fqinertpaths%%22&data=0x' \\\n"+
			"  | jq -r '.result.response.ResponseBase.Data' | base64 -d | grep %s\n",
			strings.TrimSuffix(cfg.remote, ":443"), shellQuote(cfg.realm))
		fmt.Fprintf(out, "\n# 4. Then the content, once the realm answers:\n")
	} else {
		fmt.Fprintf(out, "\n# Content:\n")
	}
	fmt.Fprintf(out, "#    go -C tools tool gnohome tx -all | sh\n")
	fmt.Fprintf(out, "#    (%d slot(s): %s)\n", len(local), slugList(local))
	return nil
}

func slugList(local []slotFile) string {
	s := make([]string, len(local))
	for i, l := range local {
		s[i] = l.slug
	}
	return strings.Join(s, ", ")
}

// gnotStr renders a ugnot amount as GNOT, for the human-facing report only.
func gnotStr(ugnot int64) string {
	return fmt.Sprintf("%.2f GNOT", float64(ugnot)/1e6)
}

func addpkgCmd(cfg config, pkgdir string, gas int64, dryRun bool) string {
	var b strings.Builder
	b.WriteString("gnokey maketx addpkg \\\n")
	b.WriteString("  -pkgdir " + shellQuote(pkgdir) + " \\\n")
	b.WriteString("  -pkgpath " + shellQuote(cfg.realm) + " \\\n")
	b.WriteString("  -gas-fee " + feeFor(gas) + " \\\n")
	b.WriteString("  -gas-wanted " + strconv.FormatInt(gas, 10) + " \\\n")
	b.WriteString("  -max-deposit " + strconv.FormatInt(depositCeiling(gas), 10) + "ugnot \\\n")
	b.WriteString("  -broadcast \\\n")
	if dryRun {
		b.WriteString("  -simulate only \\\n")
	}
	b.WriteString("  -chainid " + cfg.chainID + " \\\n")
	b.WriteString("  -remote " + cfg.remote + " \\\n")
	b.WriteString("  " + cfg.key + "\n")
	return b.String()
}

// depositCeiling is a deliberate max_deposit, rounded up to whole GNOT with
// headroom for the realm state the source bytes do not account for. Omitting
// the flag is not opting out: it falls back to vm:p:default_deposit, 100 GNOT
// of ceiling per message. Unlike the gas fee this one is refundable and only
// the measured byte delta is ever locked, so the ceiling costs nothing.
func depositCeiling(gas int64) int64 {
	const perGNOT = 1_000_000
	src := gas / gasPerByteWorstCase * 100 // ugnot at 100ugnot/byte
	ceiling := (src*4/perGNOT + 1) * perGNOT
	if ceiling < 5*perGNOT {
		ceiling = 5 * perGNOT
	}
	return ceiling
}
