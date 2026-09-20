// Package ownable proposes an abstraction around the ownership which provides
// various kind of owners and some composition options.
package ownable

import "chain/runtime"

type Owner interface {
	Addr() address
	Kind() Kind
	owner()
}

type Kind int

type UserOwner struct {
	addr address
}

type RealmOwner struct {
	realm runtime.Realm
}

type MembstoreOwner struct {
	// membstore.Membstore
}

type DAOOwner struct {
	// dao.DAO
}

func And(a Owner, b ...Owner) Owner { panic("not implemented") }
func Or(a Owner, b ...Owner) Owner  { panic("not implemented") }
