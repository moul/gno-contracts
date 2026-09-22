package vmkit

import "errors"

// ErrNotGranted is returned by a [Host] for a capability the instance was
// never given. A guest that ignores the error and keeps going is a guest bug;
// a machine should turn it into a [Trapped] status.
var ErrNotGranted = errors.New("vmkit: capability not granted")

// Host is everything a guest program can reach outside its own memory.
//
// It is deliberately small, and deliberately handed in rather than looked up:
// a guest has exactly the authority its [Host] carries. Gno realm code has
// ambient authority through the realm frame, so the guest is where the
// capability-secure version can actually be tried.
//
// Every method must be deterministic across replays of the same block. Now
// and Height come from the chain, never from a wall clock.
type Host interface {
	// Caller is the address that called the realm running this guest.
	Caller() address
	// Origin is the address that signed the transaction.
	Origin() address
	// Now is block time in Unix seconds, never wall time.
	Now() int64
	// Height is the block height.
	Height() int64

	// Get reads from storage scoped to this instance. A miss is nil.
	Get(key []byte) []byte
	// Set writes to storage scoped to this instance.
	Set(key, val []byte)

	// Input is the immutable call input for this slice of execution: the
	// guest's calldata, argv, or stdin depending on the machine. A machine
	// tracks its own read cursor, in its snapshot, so that resuming reads
	// the byte it had not read yet.
	Input() []byte
	// Output appends to the guest's output buffer.
	Output(p []byte)

	// Emit writes a chain event. kv is a flat list of alternating keys and
	// values; an odd trailing element is dropped.
	Emit(typ string, kv ...string)
	// Send transfers amount ugnot to `to`, and returns [ErrNotGranted]
	// unless the deploying realm funded this instance with a budget.
	Send(to address, amount int64) error
	// Log records a diagnostic line. Never consensus-relevant.
	Log(msg string)
}
