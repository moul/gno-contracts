# Curated GRC20 aliases

A discovery realm layered over [`r/nt/grc20reg/v0`](https://gno.land/r/nt/grc20reg/v0).
If the curator assigns `test-alpha`, `Resolve("test-alpha")` returns its canonical
registry key.
Passing a known canonical key returns that key even when it has no alias. Unknown
inputs return the empty string. The home page lists aliases, and appending an
alias after `:` to the realm URL shows the token name and its canonical key.

The deployer is the first curator. It can nominate a user or DAO realm address
with `ProposeCurator`. The nominee must call `AcceptCurator` before gaining
write access. Only the immediate caller can exercise either role.

- `SetAlias(name, "", key)` adds an unused alias for a registered key.
- `SetAlias(name, oldKey, newKey)` changes it if `oldKey` still matches.
- `RemoveAlias(name, oldKey)` frees it if `oldKey` still matches.

Aliases use 1 to 32 lowercase ASCII letters, digits or dashes and begin and end
with a letter or digit. The directory has room for 100 aliases. Curators can
point more than one alias at the same token. Changes emit events with the
alias and canonical keys involved.

Aliases are mutable discovery hints. Show the resolved key to users and retain
that canonical key when storing preferences or preparing a token operation.
The token realm or the existing GRC20 registry handles transfers and allowances.
This prototype starts with an empty directory and no preselected DAO.
