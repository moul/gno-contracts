package main

import (
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
)

func TestDecodeQFile(t *testing.T) {
	body := func(data, log string) string {
		enc := "null"
		if data != "" {
			enc = `"` + base64.StdEncoding.EncodeToString([]byte(data)) + `"`
		}
		return fmt.Sprintf(`{"jsonrpc":"2.0","result":{"response":{"ResponseBase":{"Data":%s,"Log":%q}}}}`, enc, log)
	}

	tests := []struct {
		name    string
		raw     string
		want    string
		wantErr string
	}{
		{
			name: "a file listing",
			raw:  body("gnomod.toml\nposition.gno\n", ""),
			want: "gnomod.toml\nposition.gno\n",
		},
		{
			name: "an empty answer is still an answer",
			raw:  body("", ""),
			want: "",
		},
		{
			name:    "a node-side failure is reported from Log",
			raw:     body("", "package not found"),
			wantErr: "package not found",
		},
		{
			name:    "a JSON-RPC error is reported",
			raw:     `{"jsonrpc":"2.0","error":{"message":"boom"}}`,
			wantErr: "rpc error",
		},
		{
			// The case that cost the most to recognise: the edge answering
			// instead of the node, which is not JSON at all.
			name:    "an HTML error page names itself",
			raw:     "<html>\n<head><title>403 Forbidden</title></head>\n</html>",
			wantErr: "not a JSON-RPC answer",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := decodeQFile([]byte(tt.raw))
			if tt.wantErr != "" {
				if err == nil {
					t.Fatalf("want error containing %q, got none", tt.wantErr)
				}
				if !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("want error containing %q, got %v", tt.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("want %q, got %q", tt.want, got)
			}
		})
	}
}

func TestRetryableStatus(t *testing.T) {
	tests := []struct {
		name string
		code int
		want bool
	}{
		// 403 is retryable because this endpoint uses it for rate limiting as
		// well as for refusal, and from here the two look identical.
		// Nothing about the request changes the answer: see chainFetchUA.
		{"rate limited or refused", 403, true},
		{"too many requests", 429, true},
		{"bad gateway", 502, true},
		{"not found", 404, false},
		{"bad request", 400, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := retryableStatus(tt.code); got != tt.want {
				t.Fatalf("retryableStatus(%d) = %v, want %v", tt.code, got, tt.want)
			}
		})
	}
}
