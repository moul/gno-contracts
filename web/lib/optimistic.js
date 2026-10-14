// Optimistic UI: show a change the moment it is sent, before the chain has it.
//
// A Queue holds what was sent but is not visible on chain yet. An app adds an
// entry when the transaction goes out, draws chain state plus whatever is still
// queued (styled as pending), and on every refresh tells the queue what the
// chain now shows. An entry the chain never shows (a rejected popup, a gnokey
// command never pasted) expires and is rolled back.
//
// Three rules the callers kept getting wrong, now held here:
//   - Only an observation of the visitor's OWN write settles the visitor's
//     entry. A realm-wide count moves for strangers too (claim).
//   - An entry is anchored to a position that was actually read, never to a
//     placeholder: in JavaScript `487 - null` is 487, not an error.
//   - A refresh that answers out of order is dropped whole (ordered), or it
//     moves state backwards.

export class Queue {
  constructor({ ttl = 180_000, onExpire = () => {} } = {}) {
    this.items = [];
    this.ttl = ttl;
    this.onExpire = onExpire;
  }

  get size() { return this.items.length; }

  add(item) {
    item.at = Date.now();
    this.items.push(item);
    return item;
  }

  // remove drops one entry: its transaction failed or was cancelled.
  remove(item) { this.items = this.items.filter((x) => x !== item); }

  // settle drops every entry the chain now shows, as decided by seen(item),
  // then expires what is too old. It reports what it did, because an emptied
  // queue alone cannot tell "everything landed" from "everything rolled back":
  // `confirmed` is true only when this call settled something, expired
  // nothing, and left nothing pending.
  settle(seen) {
    const before = this.items.length;
    this.items = this.items.filter((x) => !seen(x));
    const settled = before - this.items.length;
    const now = Date.now();
    const old = this.items.filter((x) => now - x.at > this.ttl);
    for (const x of old) {
      this.remove(x);
      this.onExpire(x);
    }
    return { settled, expired: old.length, confirmed: settled > 0 && old.length === 0 && this.items.length === 0 };
  }

  // claim settles entries against writes the chain shows for the acting
  // address. Each entry carries `after`, the position (a change number, a
  // history index) last read before it was sent; each observation carries
  // `at`, its own position. An observation settles the oldest entry it fits
  // that is still waiting for a position past `after`, and each observation
  // settles at most one entry: the entries after the one it settled now wait
  // for a position past it, so the same observation, seen again on the next
  // refresh, cannot settle them too. The result also lists the `claimed`
  // entries, oldest first, each keeping its observation as `seen`.
  claim(observations, fits = () => true) {
    const used = new Set();
    const claimed = [];
    const items = this.items;
    const r = this.settle((x) => {
      const o = observations.find((o) => !used.has(o) && o.at > x.after && fits(x, o));
      if (!o) return false;
      used.add(o);
      x.seen = o;
      claimed.push(x);
      for (const y of items.slice(items.indexOf(x) + 1)) y.after = Math.max(y.after, o.at);
      return true;
    });
    return { ...r, claimed };
  }
}

// ordered guards a refresh against answers that arrive out of order. Call the
// guard at the start of a refresh; it returns a check to make once every read
// is in, before anything is written. The check is false when a refresh that
// started later has already applied its result, so a stale answer is dropped
// whole instead of moving a count or a baseline backwards.
export function ordered() {
  let started = 0, applied = 0;
  return () => {
    const id = ++started;
    return () => {
      if (id < applied) return false;
      applied = id;
      return true;
    };
  };
}
