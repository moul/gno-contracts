package gnopm

import "errors"

// Stable, machine-readable error values. Callers (realms, clients, indexers)
// switch on these rather than on message text: a realm turns them into panics,
// and the panic string is the only thing a user ever sees.
var (
	ErrInvalidPkgPath   = errors.New("gnopm: invalid package path")
	ErrInvalidRepo      = errors.New("gnopm: invalid repository URL")
	ErrInvalidCommit    = errors.New("gnopm: invalid commit id")
	ErrInvalidDir       = errors.New("gnopm: invalid directory")
	ErrInvalidRef       = errors.New("gnopm: invalid ref name")
	ErrClaimNotFound    = errors.New("gnopm: no such claim")
	ErrTooManyClaimants = errors.New("gnopm: too many claimants for this package")
)
