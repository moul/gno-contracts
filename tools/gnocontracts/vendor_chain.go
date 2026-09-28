package main

// Vendoring a dependency that exists only on a chain.
//
// `make deps` reads $GNOROOT/examples, which answers for everything that was
// merged into the monorepo. It cannot answer for a package that was only ever
// deployed: GnoSwap is the case that forced this, since r/gnoswap/* lives on
// gnoland-1 and nowhere in examples. `-from-chain <rpc>` is the fallback for
// exactly those, and only those: examples still wins whenever it has the
// package, so a dep that exists in both is vendored from the monorepo and the
// two sources cannot disagree about it.
//
// The wire format is the ABCI `vm/qfile` query. Given a package path it answers
// with the newline-separated file list; given path + "/" + name it answers with
// that file's bytes.

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// chainFetchUA names this client in rpc.gno.land's logs. It is politeness, not
// a workaround: the 403 this endpoint returns is rate limiting and nothing else.
//
// Recorded because the opposite looked true for a while. A request with curl's
// default agent 403'd and the next one with a browser agent succeeded, which
// reads as an agent filter and is not: the limit had simply expired between the
// two. A/B'd 2026-09-28 with default, custom and Go-style agents issued back to
// back, and all three answer alike, 403 while limited and 200 after. Do not
// reach for a header when this endpoint refuses you; reach for the backoff
// below.
const chainFetchUA = "gnocontracts-vendor/1"

// chainFetchTimeout bounds one query. A package is a handful of them, and a
// whole GnoSwap closure a few hundred, so a slow endpoint must not hang the run.
const chainFetchTimeout = 30 * time.Second

// fetchChainPackage returns the .gno sources and gnomod.toml of one deployed
// package, keyed by file name. Other files (README.md and friends) are dropped,
// matching copyGnoPackage: vendor/ carries what the toolchain compiles.
func fetchChainPackage(rpc, pkgpath string) (map[string]string, error) {
	listing, err := abciQFile(rpc, pkgpath)
	if err != nil {
		return nil, err
	}
	files := map[string]string{}
	for _, name := range strings.Split(listing, "\n") {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		if !strings.HasSuffix(name, ".gno") && name != "gnomod.toml" {
			continue
		}
		time.Sleep(chainFetchPace)
		body, err := abciQFile(rpc, pkgpath+"/"+name)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		files[name] = body
	}
	if len(files) == 0 {
		return nil, fmt.Errorf("no .gno files at %q", pkgpath)
	}
	return files, nil
}

// chainFetchAttempts bounds the retry of a transient failure. rpc.gno.land
// intermittently answers 403 under load, and a whole-closure vendor run is a
// few hundred queries, so without a retry a run of any size ends on one of
// them. The delay doubles from chainFetchBackoff.
const (
	chainFetchAttempts = 6
	chainFetchBackoff  = 2 * time.Second
	chainFetchMaxDelay = 60 * time.Second
)

// chainFetchPace is the gap left between queries. Measured against
// rpc.gno.land 2026-09-28: a burst of qfile calls trips a 403 rate limit that
// clears about 30 seconds later when the burst stops, and sooner than a whole
// closure fetched flat out ever will, since every retry feeds the same limiter.
// Pacing is what makes the run finish; the backoff is only the safety net.
const chainFetchPace = 150 * time.Millisecond

// abciQFile runs one vm/qfile query and returns its decoded body, retrying a
// transport error or a 5xx/429/403 a bounded number of times. A 404 or any
// other definite answer is returned on the first try: retrying it only makes
// the run slower before it fails the same way.
func abciQFile(rpc, data string) (string, error) {
	var lastErr error
	delay := chainFetchBackoff
	for attempt := 0; attempt < chainFetchAttempts; attempt++ {
		if attempt > 0 {
			time.Sleep(delay)
			if delay *= 2; delay > chainFetchMaxDelay {
				delay = chainFetchMaxDelay
			}
		}
		body, retryable, err := abciQFileOnce(rpc, data)
		if err == nil {
			return body, nil
		}
		lastErr = err
		if !retryable {
			return "", err
		}
	}
	return "", fmt.Errorf("after %d attempts: %w", chainFetchAttempts, lastErr)
}

// abciQFileOnce is one attempt. It reports whether the failure is worth another.
func abciQFileOnce(rpc, data string) (body string, retryable bool, err error) {
	endpoint := strings.TrimSuffix(rpc, "/") + "/abci_query?path=" +
		url.QueryEscape(`"vm/qfile"`) + "&data=0x" + hex.EncodeToString([]byte(data))

	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return "", false, err
	}
	req.Header.Set("User-Agent", chainFetchUA)

	client := &http.Client{Timeout: chainFetchTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return "", true, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return "", true, err
	}
	if resp.StatusCode != http.StatusOK {
		return "", retryableStatus(resp.StatusCode), fmt.Errorf("%s: HTTP %d", data, resp.StatusCode)
	}
	out, err := decodeQFile(raw)
	if err != nil {
		return "", false, err
	}
	return out, false, nil
}

// retryableStatus classifies an HTTP status. 403 is in the list because this
// endpoint uses it for rate limiting as well as for refusal, and the two are
// indistinguishable from here.
func retryableStatus(code int) bool {
	return code == http.StatusForbidden ||
		code == http.StatusTooManyRequests ||
		code >= http.StatusInternalServerError
}

// decodeQFile pulls the answer out of a JSON-RPC abci_query response. Split from
// the request so it can be tested against a recorded body with no chain.
func decodeQFile(raw []byte) (string, error) {
	var env struct {
		Error  *json.RawMessage `json:"error"`
		Result struct {
			Response struct {
				ResponseBase struct {
					// Data is base64 in the wire format; encoding/json
					// decodes a []byte field from base64 for us.
					Data []byte `json:"Data"`
					Log  string `json:"Log"`
				} `json:"ResponseBase"`
			} `json:"response"`
		} `json:"result"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		// A non-JSON body is the edge answering instead of the node: an HTML
		// 403 or 502 page. Say so with a snippet rather than a parse error.
		snippet := strings.TrimSpace(string(raw))
		if len(snippet) > 120 {
			snippet = snippet[:120]
		}
		return "", fmt.Errorf("not a JSON-RPC answer: %s", snippet)
	}
	if env.Error != nil {
		return "", fmt.Errorf("rpc error: %s", string(*env.Error))
	}
	base := env.Result.Response.ResponseBase
	if base.Log != "" {
		return "", fmt.Errorf("query failed: %s", base.Log)
	}
	return string(base.Data), nil
}
