# `gno.land/r/moul/x/plan9/ns/v0`

**A Plan 9 namespace server for gno.land.** Every account gets a private,
persistent namespace: its own RAM root plus a mount table it alone controls.
Realms publish file trees into `/srv`, accounts `bind` those trees wherever they
like, and a read-only `rc` shell renders the whole thing in gnoweb.

```sh
gnokey maketx call -pkgpath gno.land/r/moul/x/plan9/ns/v0 \
  -func Exec -args 'bind -ac /srv/dev /dev; echo hello > /tmp/greeting'
```

Then browse it at `/r/moul/x/plan9/ns/v0:ns?u=<your address>`.

This is the part of Plan 9 that gno does not otherwise have. The chain has a
single global tree of realm paths that looks the same to everybody; here a name
means what *you* bound it to. Composing two realms that were never written to
work together stops being a redeploy and becomes a transaction.

## Surface

| call | what it does |
|---|---|
| `Post(cur, name, f)` | publish a `ninep.File` tree under `/srv/<name>` |
| `Unpost(cur, name)` | withdraw it; only the posting realm may |
| `Exec(cur, line)` | run an `rc` command line against the caller's namespace |
| `Reset(cur)` | throw the caller's namespace away |
| `Run(key, line)` | the read-only query side, used by `Render` |
| `Namespace(key)` | the mount table, in `ns(1)` format |

`Render` routes: `ns`, `ls/<path>`, `cat/<path>`, `stat/<path>`, `walk/<path>`,
and `rc?c=<command>` for any read-only command line. `?u=` picks whose namespace;
it defaults to a seeded demo one, so gnoweb shows something live with no
transaction.

## The default namespace

This chain's `/lib/namespace`: a private ram root, the mount points Plan 9
requires to exist before anything can be bound onto them, `/srv` mounted, and
`/dev` bound from it when a device server has been posted.

```
mount #s /srv
bind /srv/dev /dev
```

## Security

**Mounted trees are read-only by construction.** `ninep.File` has no mutating
method, so grafting a foreign realm's tree into your namespace cannot be turned
into a write against that realm; writes only ever reach a memfs tree this realm
created for you. A crossing write method would mint *this* realm's frame for the
callee, which is the confused-deputy shape `r/gov/dao`'s `Executor` relies on
deliberately and `p/nt/grc20`'s `Teller` refuses deliberately. It is out of
scope for v0 and the three filetests here pin the boundary.

`/srv` names are first come, first served, with the posting realm recorded and
the only one allowed to unpost. Squatting is possible and accepted for an
experiment.

Built on [`ninep`](../../../../../p/moul/x/plan9/ninep/v0),
[`memfs`](../../../../../p/moul/x/plan9/memfs/v0),
[`ns`](../../../../../p/moul/x/plan9/ns/v0) and
[`rc`](../../../../../p/moul/x/plan9/rc/v0). Design and analysis:
[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
