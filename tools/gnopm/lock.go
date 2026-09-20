package main

import "github.com/moul/gno-contracts/tools/gnopm/pkg/gnomodlock"

// The gnomod.lock format lives in its own package because more than one
// program reads it: the catalog tooling has to know about versions that no
// longer have a directory. These aliases keep gnopm's own code reading in
// terms of the thing it manipulates rather than in terms of the import path.
type (
	Lock      = gnomodlock.Lock
	LockEntry = gnomodlock.LockEntry
	Source    = gnomodlock.Source
)

const (
	lockFile   = gnomodlock.LockFile
	lockFormat = gnomodlock.FormatVersion
)

var (
	readLock  = gnomodlock.Read
	writeLock = gnomodlock.Write
	parseLock = gnomodlock.Parse
	unquote   = gnomodlock.Unquote
)
