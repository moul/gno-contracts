package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

// Retrying a read that the endpoint refused for reasons that are not about the
// request.
//
// rpc.gno.land sits behind an AWS load balancer that intermittently answers a
// bare 403 to a source it has decided to throttle. There is no Retry-After, no
// rate-limit header and no body: nothing to back off against, and nothing that
// distinguishes it from a permanent denial except that the very next request
// often succeeds. Observed from two different hosts on 2026-09-24 and
// 2026-09-28, minutes apart, while the same endpoint answered 200 to another.
//
// That matters here more than anywhere else in this tool. `tx -run` reads the
// account before it can build anything, so a single 403 on the first call ends
// the whole push with nothing done, which is exactly what happened to
// `make home-push` the first time it was used for real.
//
// 403 is normally the one status it is wrong to retry: it means "no, and asking
// again will not help". It is retried here, deliberately and narrowly, because
// this endpoint is an UNAUTHENTICATED public read. There is no credential to be
// wrong, so a 403 cannot mean what 403 usually means, and the only reading left
// is that the edge refused to pass the request on. If gnohome ever learns to
// read an endpoint that takes a credential, this must be revisited.

const (
	// maxAttempts is the initial try plus four more.
	maxAttempts = 5
	// baseBackoff doubles each attempt: 1s, 2s, 4s, 8s, so a call gives up
	// after about 15s rather than hanging a Makefile target indefinitely.
	baseBackoff = time.Second
)

// sleep is a variable so a test can run the backoff without waiting for it.
var sleep = time.Sleep

// retryableStatus reports whether an HTTP status is worth asking again.
//
// 5xx and 429 are the ordinary cases. 403 is the gno.land edge block described
// above. Everything else, in particular 400 and 404, is an answer: the request
// was understood and the response will not change.
func retryableStatus(code int) bool {
	switch {
	case code == http.StatusForbidden, code == http.StatusTooManyRequests:
		return true
	case code >= 500:
		return true
	default:
		return false
	}
}

// withRetry calls do until it succeeds, it fails in a way that will not change,
// or the attempts run out.
//
// retry reports whether the error do returned is transient. A nil error stops
// immediately, and so does an error retry rejects: an ABCI-level error is a
// real answer from a healthy node, and repeating a query for a package that
// does not exist would turn a clear message into a slow one.
func withRetry(what string, do func() error, retry func(error) bool) error {
	var err error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		err = do()
		if err == nil || !retry(err) {
			return err
		}
		if attempt == maxAttempts {
			break
		}
		wait := baseBackoff * time.Duration(1<<(attempt-1))
		fmt.Fprintf(os.Stderr, "gnohome: %s: %v; retrying in %s (%d/%d)\n",
			what, err, wait, attempt, maxAttempts-1)
		sleep(wait)
	}
	return fmt.Errorf("%s: gave up after %d attempts: %w", what, maxAttempts, err)
}

// transientError marks an error withRetry should retry. Wrapping rather than
// inspecting strings, so the decision is made once, where the status code and
// the network error are still distinguishable from each other.
type transientError struct{ err error }

func (e transientError) Error() string { return e.err.Error() }
func (e transientError) Unwrap() error { return e.err }

func isTransient(err error) bool {
	_, ok := err.(transientError)
	return ok
}
