# `selfreg` — self-registering implementation (pattern E)

The permanent path holds an interface value and no business logic. A new
implementation realm takes the facade over **by being deployed**: it registers
itself from its own `init`. Callers never learn that a version exists.

```
selfreg/facade/v0   permanent; holds an Impl, forwards Greet/Version/Render
selfreg/impl/v0     registers itself on init
selfreg/impl/v1     registers itself on init, and wins
```

**Deploying is the upgrade.** That is the appeal and it is also the entire risk:
whoever can deploy under the guarded prefix can take the realm over with no
second signature from anybody. If that is not what you want, the split version
is [`adminreg`](../adminreg).

The gate is an explicit path prefix. gno ships `p/nt/nestedpkg/v0` for exactly
this, but neither helper fits: `AssertCallerIsSubPath` wants the implementation
nested under the facade, and with the version segment last no sibling is a
sub-path of another; `IsSameNamespace` would let any realm in the namespace
seize the facade. The caller's path is read off the crossing frame, so there is
no argument to forge — the outsider filetest in `facade/v0` proves the refusal.

The interface itself is frozen at deploy, like every Go interface. Growing the
API means an extension realm, or an API declared as data instead of as a type
(see the notes on prior art in [../README.md](../README.md)).

Run it: `gno test ./r/moul/x/upgrade/selfreg/...`
