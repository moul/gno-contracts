// A small markdown renderer for what realms emit: headings, lists, tables,
// code, quotes, links, images. Everything is escaped first and only known tags
// are produced, so a realm cannot inject HTML into the page. gnoweb's own tags
// (<gno-columns>, …) are dropped rather than rendered.

const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// link maps a gnoweb href to one this page can follow. `/r/...` and `:args`
// stay in the dashboard; `$help`, `$source` and friends go to gnoweb itself.
export function makeLinker(pkgpath, webBase) {
  const realm = pkgpath.replace(/^gno\.land/, "");
  return (href) => {
    href = href.trim();
    if (/^https?:\/\//i.test(href)) return { href, external: true };
    if (href.startsWith(":")) href = realm + href;
    if (href.startsWith("?") || href === "") href = realm + href;
    if (/^\/[rp]\//.test(href)) {
      if (href.includes("$")) return { href: webBase + href, external: true };
      return { href: "#" + href, external: false };
    }
    if (href.startsWith("/")) return { href: webBase + href, external: true };
    if (href.startsWith("#")) return { href, external: false };
    return null; // javascript:, data:, anything else: rendered as text
  };
}

function inline(s, link) {
  const codes = [];
  s = s.replace(/`([^`]+)`/g, (_, c) => `\u0000${codes.push(c) - 1}\u0000`);
  s = esc(s);
  s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/g, (_, alt, src) =>
    /^https:\/\//.test(src) ? `<img alt="${alt}" src="${src}" loading="lazy">` : alt);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)[^)]*\)/g, (_, text, href) => {
    const l = link(href.replace(/&amp;/g, "&"));
    if (!l) return text;
    return `<a href="${esc(l.href)}"${l.external ? ' target="_blank" rel="noopener"' : ""}>${text}</a>`;
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/__([^_]+)__/g, "<strong>$1</strong>");
  s = s.replace(/(^|[^*\w])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>").replace(/(^|\W)_([^_\s][^_]*)_(?=\W|$)/g, "$1<em>$2</em>");
  s = s.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${esc(codes[i])}</code>`);
}

const cells = (row) => row.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());

export function render(md, link) {
  const lines = md.replace(/\r/g, "").split("\n");
  const out = [];
  let para = [];
  const flush = () => { if (para.length) out.push(`<p>${inline(para.join(" "), link)}</p>`); para = []; };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    let m;
    if (/^\s*<\/?gno-[\w-]+[^>]*>\s*$/.test(line)) { flush(); continue; }
    if ((m = line.match(/^```\s*(\S*)/))) {
      flush();
      const body = [];
      while (++i < lines.length && !/^```/.test(lines[i])) body.push(lines[i]);
      out.push(`<pre><code>${esc(body.join("\n"))}</code></pre>`);
    } else if ((m = line.match(/^(#{1,6})\s+(.*)/))) {
      flush();
      out.push(`<h${m[1].length}>${inline(m[2], link)}</h${m[1].length}>`);
    } else if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
      flush();
      out.push("<hr>");
    } else if (/^\s*\|.*\|\s*$/.test(line) && /^\s*\|?[\s:|-]+\|?\s*$/.test(lines[i + 1] || "") && lines[i + 1].includes("-")) {
      flush();
      const head = cells(line).map((c) => `<th>${inline(c, link)}</th>`).join("");
      const rows = [];
      for (i += 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) {
        rows.push(`<tr>${cells(lines[i]).map((c) => `<td>${inline(c, link)}</td>`).join("")}</tr>`);
      }
      i--;
      out.push(`<div class="table"><table><thead><tr>${head}</tr></thead><tbody>${rows.join("")}</tbody></table></div>`);
    } else if (/^>\s?/.test(line)) {
      flush();
      const body = [];
      for (; i < lines.length && /^>\s?/.test(lines[i]); i++) body.push(lines[i].replace(/^>\s?/, ""));
      i--;
      out.push(`<blockquote>${render(body.join("\n"), link)}</blockquote>`);
    } else if ((m = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)/))) {
      flush();
      const ordered = /\d/.test(m[2]);
      const items = [];
      for (; i < lines.length && (m = lines[i].match(/^\s*([-*+]|\d+[.)])\s+(.*)/)); i++) {
        items.push(`<li>${inline(m[2].replace(/^\[( |x)\]\s*/i, (_, x) => (x === " " ? "☐ " : "☑ ")), link)}</li>`);
      }
      i--;
      out.push(ordered ? `<ol>${items.join("")}</ol>` : `<ul>${items.join("")}</ul>`);
    } else if (line.trim() === "") {
      flush();
    } else {
      para.push(line.trim());
    }
  }
  flush();
  return out.join("\n");
}
