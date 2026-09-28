package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// noSleep makes the backoff instant, so a test of five attempts does not take
// fifteen seconds. Restored after, or every later test pays the real wait.
func noSleep(t *testing.T) {
	t.Helper()
	prev := sleep
	sleep = func(time.Duration) {}
	t.Cleanup(func() { sleep = prev })
}

// abciOK is a minimal successful abci_query response carrying base64 "hi".
const abciOK = `{"jsonrpc":"2.0","id":1,"result":{"response":{"ResponseBase":{"Data":"aGk="}}}}`

// TestAbciQueryRetriesTheEdge403 is the defect this exists for.
//
// rpc.gno.land answers a bare 403 from its load balancer to a source it has
// decided to throttle, with no Retry-After and no body, and the next request
// often succeeds. `tx -run` reads the account before it can build anything, so
// one 403 on the first call ended the whole push with nothing done. That is
// exactly how `make home-push` failed the first time it was used for real.
func TestAbciQueryRetriesTheEdge403(t *testing.T) {
	noSleep(t)
	var calls int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls < 3 {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.Write([]byte(abciOK))
	}))
	defer srv.Close()

	got, err := abciQuery(srv.URL, "vm/qeval", "x")
	if err != nil {
		t.Fatalf("gave up on a 403 that cleared: %v", err)
	}
	// Data is base64 on the wire and decoded by encoding/json into []byte,
	// so what abciQuery returns is the plaintext, not "aGk=".
	if got != "hi" {
		t.Errorf("data = %q, want the decoded response", got)
	}
	if calls != 3 {
		t.Errorf("made %d call(s), want 3: two refusals then the answer", calls)
	}
}

// TestAbciQueryGivesUpEventually. A retry that never stops is worse than the
// failure: a Makefile target that hangs forever cannot be distinguished from
// one that is working.
func TestAbciQueryGivesUpEventually(t *testing.T) {
	noSleep(t)
	var calls int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()

	_, err := abciQuery(srv.URL, "vm/qeval", "x")
	if err == nil {
		t.Fatal("a permanently refusing endpoint returned no error")
	}
	if calls != maxAttempts {
		t.Errorf("made %d call(s), want %d", calls, maxAttempts)
	}
	if !strings.Contains(err.Error(), "gave up") {
		t.Errorf("error does not say it gave up, so a reader cannot tell it was retried: %v", err)
	}
}

// TestAbciQueryDoesNotRetryAnAnswer is the other half, and the one that keeps
// this from making every real error slow.
//
// An ABCI error is a healthy node replying "that package does not exist". A 400
// is the request being wrong. Neither changes on a second ask, and retrying
// would turn a clear message into a fifteen-second one.
func TestAbciQueryDoesNotRetryAnAnswer(t *testing.T) {
	noSleep(t)
	for _, tc := range []struct {
		name string
		body func(w http.ResponseWriter)
	}{
		{"abci error", func(w http.ResponseWriter) {
			w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"response":{"ResponseBase":{` +
				`"Error":{"@type":"/vm.InvalidPkgPathError"},"Log":"banner\n 0 x - package not found"}}}}`))
		}},
		{"bad request", func(w http.ResponseWriter) { w.WriteHeader(http.StatusBadRequest) }},
		{"not found", func(w http.ResponseWriter) { w.WriteHeader(http.StatusNotFound) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var calls int
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				tc.body(w)
			}))
			defer srv.Close()

			if _, err := abciQuery(srv.URL, "vm/qeval", "x"); err == nil {
				t.Fatal("want an error")
			}
			if calls != 1 {
				t.Errorf("made %d call(s), want 1: this is an answer, not a refusal", calls)
			}
		})
	}
}

// TestRetryableStatus pins which codes are transient, because 403 is normally
// the one status it is wrong to retry. It is retried here only because the
// endpoint is an unauthenticated public read, where there is no credential that
// could be wrong, so 403 cannot mean what it usually means.
func TestRetryableStatus(t *testing.T) {
	for code, want := range map[int]bool{
		200: false, 400: false, 404: false, 422: false,
		403: true, 429: true, 500: true, 502: true, 503: true,
	} {
		if got := retryableStatus(code); got != want {
			t.Errorf("retryableStatus(%d) = %v, want %v", code, got, want)
		}
	}
}
