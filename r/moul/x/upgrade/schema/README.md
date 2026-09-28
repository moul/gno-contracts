# `schema`: the API as data (pattern G)

Patterns [`selfreg`](../selfreg) and [`adminreg`](../adminreg) put a Go interface at
the permanent path, which fixes the method set at deploy: adding an operation later
needs a whole extra realm. This one puts a single entry point there instead,

```go
Call(cur realm, verb, payload string) string
```

and moves the API into **data** that each handler declares. The signature committed
to forever is that one line; everything the application does can still grow.

```
schema/facade      permanent; parses the declared schema, checks payloads, dispatches
schema/impl/gen0   verbs: upper, repeat
schema/impl/gen1   adds surround, keeps both of v0's, so it is accepted
schema/impl/bad    satisfies Handler perfectly, drops a verb, and is refused
```

Three things fall out of the API being data, and they are why you would pay for it:

1. **Callers enumerate it.** `Verbs`, `Signature` and `SchemaText` answer with no
   transaction, so a client discovers the API instead of being compiled against it.
2. **Payloads are checked before the handler runs**, so a wrong argument count is one
   abort naming the signature rather than whatever the handler does with it.
3. **Upgrades are diffed.** `Accept` refuses a handler whose schema drops or reshapes
   a verb, which no amount of interface satisfaction can catch: `impl/bad` compiles,
   satisfies `Handler`, proposes itself, and is still refused.

**The diff is symmetric, and that is the part worth knowing.** Once `gen1` has added
a verb, rolling back to `gen0` drops it and is a regression by the same rule that
protects callers going forward. A pattern that can only move forward is worse than one
with no diff at all, so `AcceptBreaking` exists: same owner gate, different word, and
the audit log shows which one was used.

**What it costs**, measured on gno master with 101 dispatches through each pattern's
own entry point:

| pattern | entry point | gas, 101 calls | gas per call | allocs |
|---|---|---|---|---|
| `adminreg` | typed, `Greet(name)` | 945,856 | ~9,400 | 208.1k |
| `schema` | string, `Call(cur, verb, payload)` | 18,409,550 | ~182,000 | 1.7M |

That is **19.5x**, which is large enough to decide a design rather than to shrug at.

```sh
gno test -v -print-runtime-metrics -run TestDispatchCost100 ./r/moul/x/upgrade/schema/impl/gen1
gno test -v -print-runtime-metrics -run TestDispatchCost100 ./r/moul/x/upgrade/adminreg/impl/gen1
```

Read that as the cost of each pattern **as shipped**, which is the number that decides
between them, and not as the cost of the string boundary in isolation: the schema path
also crosses a realm and the typed one does not. Separating the two is an open thread.

**State is out of scope here.** These handlers are pure. Where an application's data
should live is [`store`](../store)'s question, and the answer does not change because
the entry point became a string.

Run it: `gno test ./r/moul/x/upgrade/schema/...`
