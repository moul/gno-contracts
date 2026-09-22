package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// remoteSlot is one line of the realm's Manifest().
type remoteSlot struct {
	rev  int
	size int
	hash string
}

// fetchManifest reads <realm>.Manifest() over JSON-RPC abci_query. That is one
// round trip for the whole diff: the manifest carries a hash per slot, so no
// body is ever downloaded just to find out it has not changed.
//
// Returns an empty map when the realm is not deployed yet, so `status` on a
// fresh chain reports "everything is missing" instead of failing.
func fetchManifest(remote, realm string) (map[string]remoteSlot, error) {
	raw, err := qeval(remote, realm+".Manifest()")
	if err != nil {
		if strings.Contains(err.Error(), "package not found") ||
			strings.Contains(err.Error(), "is not available") {
			return map[string]remoteSlot{}, nil
		}
		return nil, err
	}
	return parseManifest(raw)
}

func parseManifest(raw string) (map[string]remoteSlot, error) {
	out := map[string]remoteSlot{}
	for _, line := range strings.Split(raw, "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) != 4 {
			return nil, fmt.Errorf("manifest line has %d fields, want 4: %q", len(f), line)
		}
		rev, err := strconv.Atoi(f[1])
		if err != nil {
			return nil, fmt.Errorf("manifest line %q: bad rev: %w", line, err)
		}
		size, err := strconv.Atoi(f[2])
		if err != nil {
			return nil, fmt.Errorf("manifest line %q: bad size: %w", line, err)
		}
		out[f[0]] = remoteSlot{rev: rev, size: size, hash: f[3]}
	}
	return out, nil
}

type rpcResponse struct {
	Error  *json.RawMessage `json:"error"`
	Result struct {
		Response struct {
			ResponseBase struct {
				Error *struct {
					Type string `json:"@type"`
				} `json:"Error"`
				Data []byte `json:"Data"` // base64 in JSON
				Log  string `json:"Log"`
			} `json:"ResponseBase"`
		} `json:"response"`
	} `json:"result"`
}

// qeval evaluates a pure expression on the chain and returns the string it
// produced. The VM answers with an amino-printed value, `("…" string)`, so
// the quoted payload is unwrapped here.
// qeval evaluates a gno expression and unwraps the `("…" string)` envelope
// that vm/qeval alone puts around its result. Every other ABCI path returns
// raw bytes, so unwrapping belongs here and not in abciQuery: applying it to
// vm/qfile or vm/qinertpaths turns a perfectly good answer into an error, and
// a caller reading that error as "absent" reports live packages as missing.
func qeval(remote, expr string) (string, error) {
	raw, err := abciQuery(remote, "vm/qeval", expr)
	if err != nil {
		return "", err
	}
	return unwrapString(raw)
}

// abciQuery is the one network call this tool makes: a JSON-RPC abci_query,
// standard library only, no gnoclient. `path` is the ABCI path (vm/qeval,
// vm/qfile, vm/qinertpaths) and `data` its argument.
func abciQuery(remote, path, data string) (string, error) {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "abci_query",
		"params": map[string]any{
			"path":   path,
			"data":   base64.StdEncoding.EncodeToString([]byte(data)),
			"height": "0",
			"prove":  false,
		},
	})
	if err != nil {
		return "", err
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Post(remote, "application/json", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("querying %s: %w", remote, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("querying %s: HTTP %s", remote, resp.Status)
	}

	var out rpcResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("decoding the response from %s: %w", remote, err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("rpc error: %s", string(*out.Error))
	}
	if e := out.Result.Response.ResponseBase.Error; e != nil {
		// The Log carries the useful detail; its first line is the generic
		// banner, so the message after "- " is what a reader wants.
		return "", fmt.Errorf("%s: %s", e.Type, firstTrace(out.Result.Response.ResponseBase.Log))
	}
	return string(out.Result.Response.ResponseBase.Data), nil
}

// firstTrace pulls the human-readable cause out of an ABCI error log.
func firstTrace(log string) string {
	for _, line := range strings.Split(log, "\n") {
		if i := strings.Index(line, " - "); i >= 0 {
			return strings.TrimSpace(line[i+3:])
		}
	}
	return strings.TrimSpace(log)
}

// unwrapString turns the VM's `("…" string)` rendering into the string itself.
func unwrapString(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", nil
	}
	if !strings.HasPrefix(s, "(") || !strings.HasSuffix(s, " string)") {
		return "", fmt.Errorf("unexpected qeval result shape: %q", s)
	}
	quoted := strings.TrimSuffix(strings.TrimPrefix(s, "("), " string)")
	v, err := strconv.Unquote(quoted)
	if err != nil {
		return "", fmt.Errorf("unquoting the qeval result: %w", err)
	}
	return v, nil
}
