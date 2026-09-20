# `gno.land/r/moul/x/framelab/probe/v0`

The realm half of the `p/moul/x/framelab/v0` probe: shaped exactly like a
generated instance realm (state here, logic in the pure package, one-line
re-exports forwarding `cur`), and used only to assert which realm frame the pure
package runs in.

Not useful on chain. It exists so the property the instance-per-realm pattern
depends on has a test that fails loudly if a future gno release changes it.
