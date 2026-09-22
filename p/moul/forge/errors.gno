package forge

import "errors"

// Stable, machine-readable error values. Callers (realms, clients, indexers)
// should switch on these rather than on message text: a realm turns them into
// panics, and the panic string is the only thing a user sees.
var (
	ErrInvalidRepoID     = errors.New("forge: invalid repo id")
	ErrInvalidRefName    = errors.New("forge: invalid ref name")
	ErrInvalidOID        = errors.New("forge: invalid object id")
	ErrInvalidText       = errors.New("forge: invalid text")
	ErrInvalidRole       = errors.New("forge: invalid role")
	ErrInvalidVerdict    = errors.New("forge: invalid review verdict")
	ErrInvalidMirror     = errors.New("forge: invalid mirror locator")
	ErrTooLong           = errors.New("forge: value too long")
	ErrTooMany           = errors.New("forge: too many entries")
	ErrRepoExists        = errors.New("forge: repo already exists")
	ErrRepoNotFound      = errors.New("forge: repo not found")
	ErrRepoArchived      = errors.New("forge: repo is archived")
	ErrRefNotFound       = errors.New("forge: ref not found")
	ErrRefExists         = errors.New("forge: ref already exists")
	ErrStaleRef          = errors.New("forge: stale ref (compare-and-swap failed)")
	ErrUnauthorized      = errors.New("forge: unauthorized")
	ErrIssueNotFound     = errors.New("forge: issue not found")
	ErrIssueClosed       = errors.New("forge: issue is closed")
	ErrChangeNotFound    = errors.New("forge: change not found")
	ErrChangeNotOpen     = errors.New("forge: change is not open")
	ErrSelfApproval      = errors.New("forge: self-approval is not allowed")
	ErrNotEnoughApproval = errors.New("forge: not enough approvals")
	ErrChangesRequested  = errors.New("forge: changes requested by a reviewer")
	ErrSameOID           = errors.New("forge: ref already points at that object")
	ErrLastOwner         = errors.New("forge: cannot demote the last owner")
)
