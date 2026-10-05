// Optimistic UI: show a change the moment it is sent, before the chain has it.
//
// A Queue holds what was sent but is not visible on chain yet. An app adds an
// entry when the transaction goes out, draws chain state plus whatever is still
// queued (styled as pending), and on every refresh tells the queue how far the
// chain has caught up. An entry the chain never shows (a rejected popup, a
// gnokey command never pasted) expires and is rolled back.

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

  // settle drops every entry the chain now shows, as decided by seen(item).
  settle(seen) {
    this.items = this.items.filter((x) => !seen(x));
    const now = Date.now();
    for (const x of this.items.filter((x) => now - x.at > this.ttl)) {
      this.remove(x);
      this.onExpire(x);
    }
  }

  // take settles the oldest n entries: for a realm that only exposes a count.
  take(n) {
    if (n > 0) this.items.splice(0, n);
    this.settle(() => false);
  }
}
