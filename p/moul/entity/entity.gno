// Package entity provides an interface that abstracts a notion of entity which
// can under the hood be an EOA (address), a package realm (PkgPath, address).
// It also tries to give a notion of type where for instance, a user can be
// either a simple user or a team, and a contract can be either an arbitrary
// contract, or one that implements a famous pattern/interface, such as a DAO.
// It also provides some composition utilities so that an entity can be a flow
// that matches multiple other entities.
package entity

import (
	"chain/runtime"
)

type Entity interface {
	Addr() address
	Path() string
	Kind
	isEntity()
}

type Kind interface {
	kind()
}

type UserEntity interface {
	Entity
	isUserEntity()
}

type RealmEntity interface {
	Entity
	isRealmEntity()
}

func NewUserByAddr(addr address) UserEntity  { panic("not implemented") }
func NewUserByName(name string) UserEntity   { panic("not implemented") }
func NewRealm(rlm runtime.Realm) RealmEntity { panic("not implemented") }
