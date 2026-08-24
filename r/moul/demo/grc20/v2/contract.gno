package grc20

import (
	"chain/runtime/unsafe"

	tokens "gno.land/p/demo/tokens/grc20"
)

// test1 receives the initial mint at construction.
var test1 = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

// Token is exported. Other contracts can read it (balances, metadata).
// privateLedger stays unexported: it grants unrestricted mint/burn/transfer.
var (
	Token         *tokens.Token
	privateLedger *tokens.PrivateLedger
)

func init(cur realm) {
	// generate the token and mint some tokens to test1.
	Token, privateLedger = tokens.NewToken("Foo Token", "FOO", 4, 0, cur)
	privateLedger.Mint(test1, 100000000)
}

func MyBalance() int64 {
	return Token.BalanceOf(unsafe.OriginCaller())
}
