# Ballot

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A Gno port of the classic Solidity "Ballot" voting contract: a chairperson seeds a fixed list of proposals and grants specific addresses the right to vote, and each voter either casts a direct vote or delegates their weight down a delegation chain (with a loop guard, just like the original). WinningProposal/WinnerName report the current leader live, so there's no separate close-the-vote step. It's neat because delegation composability - a delegate's weight can itself be re-delegated - is the one part of the original contract that's easy to get subtly wrong, and this port keeps that chain-walking + cycle-detection logic faithful while swapping mappings for an avl.Tree.

Built for topaz (gno 0.9). Live demo (agent address): https://topaz.testnets.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/ballot
