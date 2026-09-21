package main

// Before/after screenshots of the packages a pull request changed.
//
// Adapted from gnolang/gno#6194 (misc/gnopreview/shots.go); the fixed
// gnoweb-chrome sample it also carries has no counterpart here, because nothing
// in this repository changes gnoweb.

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// shotsDir is where screenshots land inside the published snapshot, so the pull
// request comment can embed them by URL without uploading anything.
const shotsDir = "_shots"

// beforeDir holds the same packages rendered from the merge base.
const beforeDir = "_before"

// maxPairs caps how many changed packages get a before/after pair. Four images
// is already a lot of comment; the full list is right underneath.
const maxPairs = 2

// shotPair is one package shown before and after the pull request's change.
type shotPair struct {
	Pkg    string `json:"pkg"`
	Before string `json:"before,omitempty"`
	After  string `json:"after"`
	URL    string `json:"url"` // the after page, for the link behind the image
	// New says the package does not exist at the merge base, which is why
	// there is no "before". Distinct from Before being empty because no base
	// checkout was supplied at all: claiming a package is new when we simply
	// did not look would be a lie in the comment.
	New bool `json:"new,omitempty"`
}

// screenshotPairs photographs each changed package as the merge base renders it
// and as this branch renders it. Both passes use the SAME gnoweb (the binary
// and the assets come from the head), so what the pair shows is the package
// change and nothing else.
func screenshotPairs(outDir string, head, base *Crawler, pkgs []string, newPkgs map[string]bool, chrome string) []shotPair {
	bin := findChrome(chrome)
	if bin == "" {
		fmt.Fprintln(os.Stderr, "  ! no Chrome/Chromium found — publishing the preview without before/after")
		return nil
	}
	srv, origin, err := serveDir(outDir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "  ! screenshot server:", err)
		return nil
	}
	defer srv.Close()
	if err := os.MkdirAll(filepath.Join(outDir, shotsDir), 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "  !", err)
		return nil
	}
	var pairs []shotPair
	for _, r := range pkgs {
		if len(pairs) >= maxPairs {
			fmt.Fprintf(os.Stderr, "  i before/after capped at %d package(s); the rest are listed as links\n", maxPairs)
			break
		}
		afterFile, ok := head.FileOf(gnowebPath(r))
		if !ok {
			continue
		}
		name := slug(strings.TrimPrefix(gnowebPath(r), "/"))
		pair := shotPair{Pkg: r, URL: path.Dir(afterFile) + "/", New: newPkgs[r]}
		if err := chromeShot(bin, origin+"/"+afterFile,
			filepath.Join(outDir, shotsDir, name+"-after.png")); err != nil {
			fmt.Fprintf(os.Stderr, "  ! screenshot %s (after): %v\n", r, err)
			continue
		}
		pair.After = path.Join(shotsDir, name+"-after.png")

		// "New in this PR" is asserted only from the merge-base tree, never
		// inferred from a missing capture: a base pass that ran but failed on
		// this package would otherwise be reported as the package not existing.
		if base != nil {
			if beforeFile, ok := base.FileOf(gnowebPath(r)); ok {
				if err := chromeShot(bin, origin+"/"+beforeFile,
					filepath.Join(outDir, shotsDir, name+"-before.png")); err == nil {
					pair.Before = path.Join(shotsDir, name+"-before.png")
				} else {
					fmt.Fprintf(os.Stderr, "  ! screenshot %s (before): %v\n", r, err)
				}
			}
		}
		pairs = append(pairs, pair)
		fmt.Printf("  📷 %s (before/after)\n", r)
	}
	return pairs
}

// serveDir exposes the snapshot over HTTP on a loopback port. Chrome refuses to
// load ES modules over file:// (CORS), and gnoweb loads every one of its
// controllers that way, so a file:// screenshot is silently the no-JS
// rendering.
func serveDir(dir string) (io.Closer, string, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, "", err
	}
	srv := &http.Server{
		Handler:           http.FileServer(http.Dir(dir)),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go srv.Serve(ln) //nolint:errcheck // Serve always returns on Close
	return ln, "http://" + ln.Addr().String(), nil
}

func chromeShot(bin, url, dst string) error {
	out, err := filepath.Abs(dst)
	if err != nil {
		return err
	}
	cmd := exec.Command(bin,
		"--headless=new",
		"--disable-gpu",
		"--no-sandbox",
		"--hide-scrollbars",
		"--force-device-scale-factor=1",
		"--window-size=1280,860",
		// Let the controller modules load and the webfonts settle before the
		// frame is grabbed; without it the shot is unstyled text.
		"--virtual-time-budget=4000",
		"--screenshot="+out,
		url,
	)
	if b, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(b)))
	}
	if fi, err := os.Stat(out); err != nil || fi.Size() == 0 {
		return fmt.Errorf("chrome wrote no image")
	}
	return nil
}

// findChrome resolves a browser binary: the explicit flag, then $CHROME, then
// the usual Linux names, then the macOS bundle path.
func findChrome(explicit string) string {
	candidates := []string{explicit, os.Getenv("CHROME")}
	candidates = append(candidates,
		"google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
	)
	for _, c := range candidates {
		if c == "" {
			continue
		}
		if p, err := exec.LookPath(c); err == nil {
			return p
		}
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return c
		}
	}
	return ""
}
