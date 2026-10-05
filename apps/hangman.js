// Hangman: one shared word a day. The realm exposes no getter, so this reads
// the public Render and lifts the gallows, the word and the guesses out of it,
// then turns the alphabet into Guess buttons. A clicked letter shows at once
// as pending, until the chain lists it among the guesses.

import { Queue } from "../lib/optimistic.js";

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <div class="app-panel">
      <pre class="gallows" data-g></pre>
      <div class="word" data-w>…</div>
      <p data-s class="muted"></p>
      <div class="keys" data-k>${[..."abcdefghijklmnopqrstuvwxyz"].map((c) => `<button data-c="${c}">${c}</button>`).join("")}</div>
      <p class="muted" data-msg></p>
    </div>`;
  const $ = (s) => el.querySelector(s);
  let guessed = new Set(), over = false;
  const queue = new Queue({ onExpire: (x) => { $("[data-msg]").textContent = `“${x.letter}” not seen on chain after 3 minutes, rolled back`; drawKeys(); } });
  const drawKeys = () => {
    const pending = new Set(queue.items.map((x) => x.letter));
    el.querySelectorAll("[data-c]").forEach((b) => {
      b.disabled = over || guessed.has(b.dataset.c) || pending.has(b.dataset.c);
      b.classList.toggle("pending", pending.has(b.dataset.c));
    });
  };

  const refresh = async () => {
    try {
      const md = await client.render(path, "");
      $("[data-g]").textContent = (md.match(/```\n([\s\S]*?)```/) || [, ""])[1];
      $("[data-w]").textContent = (md.match(/## Word\s+`([^`]*)`/) || [, "?"])[1];
      const wrong = (md.match(/Wrong: \*\*([^*]+)\*\*/) || [, "?"])[1];
      const status = (md.match(/## Status\s+([^\n]+)/) || [, ""])[1].replace(/Call `[^`]+`.*$/, "").replace(/\*\*/g, "").trim();
      $("[data-s]").textContent = `wrong ${wrong} · ${status}`;
      const guessedLine = (md.match(/Guessed letters: ([^\n]*)/) || [, ""])[1];
      guessed = new Set([...guessedLine.matchAll(/`([a-z])`|\b([a-z])\b/g)].map((m) => m[1] || m[2]));
      over = /solved|game over/i.test(status);
      const before = queue.size;
      queue.settle((x) => guessed.has(x.letter));
      if (before && !queue.size) $("[data-msg]").textContent = "confirmed on chain";
      drawKeys();
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  };

  el.querySelectorAll("[data-c]").forEach((b) => b.addEventListener("click", async () => {
    $("[data-msg]").textContent = `guessing “${b.dataset.c}”, waiting for the wallet…`;
    let item = null;
    try {
      const tx = await call("Guess", [b.dataset.c], { onSubmit: () => { item = queue.add({ letter: b.dataset.c }); drawKeys(); } });
      $("[data-msg]").textContent = wallet.describe(tx);
      refresh();
    } catch (e) {
      if (item) { queue.remove(item); drawKeys(); }
      $("[data-msg]").textContent = e.message;
    }
  }));

  refresh();
  const timer = setInterval(refresh, 6000);
  return () => clearInterval(timer);
}
