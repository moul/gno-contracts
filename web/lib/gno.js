// A gno.land RPC client for the browser: plain JSON-RPC over fetch, no
// dependency. Every public gno RPC answers with `access-control-allow-origin: *`,
// so a static page can read any realm directly.

export const NETWORKS = {
  mainnet: { chainId: "gnoland-1", rpc: "https://rpc.gno.land:443", web: "https://gno.land" },
  onyx: { chainId: "onyx-1", rpc: "https://rpc.onyx.testnets.gno.land:443", web: "https://onyx.testnets.gno.land" },
  staging: { chainId: "staging", rpc: "https://rpc.staging.gno.land:443", web: "https://staging.gno.land" },
  local: { chainId: "dev", rpc: "http://127.0.0.1:26657", web: "http://127.0.0.1:8888" },
};

const b64encode = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const b64decode = (s) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

export class QueryError extends Error {}

export class Client {
  constructor(net) {
    this.net = net;
    this.cfg = NETWORKS[net];
  }

  async abci(path, data) {
    const res = await fetch(this.cfg.rpc, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path, data: b64encode(data) } }),
    });
    if (!res.ok) throw new QueryError(`${this.net}: HTTP ${res.status}`);
    const body = await res.json();
    if (body.error) throw new QueryError(body.error.data || body.error.message);
    const base = body.result.response.ResponseBase;
    if (base.Error) throw new QueryError(firstLine(base.Log) || base.Error["@type"]);
    return base.Data ? b64decode(base.Data) : "";
  }

  // render returns the markdown a realm's Render(path) produces.
  render(pkgpath, args = "") {
    return this.abci("vm/qrender", `${pkgpath}:${args}`);
  }

  // eval runs a read-only expression, e.g. eval("gno.land/r/x", "Value()").
  // The raw answer looks like `(2 int)`, or several of those for multiple results.
  eval(pkgpath, expr) {
    return this.abci("vm/qeval", `${pkgpath}.${expr}`);
  }

  // funcs lists a realm's exported functions with their parameter types.
  async funcs(pkgpath) {
    return JSON.parse((await this.abci("vm/qfuncs", pkgpath)) || "[]");
  }

  // file returns a file's source, or the newline-separated file list for a package.
  file(path) {
    return this.abci("vm/qfile", path);
  }
}

function firstLine(log) {
  if (!log) return "";
  const m = log.match(/Msg Traces:\s*\n\s*0\s+[^\n]*?:\s*(.*)/) || log.match(/Data: (.*)/);
  return (m ? m[1] : log.split("\n")[0]).slice(0, 300);
}

// parseEval turns `(2 int)` / `("hi" string)` into a JS value. Good enough for
// the scalar results a demo reads; anything else comes back as the raw text.
export function parseEval(raw) {
  const m = raw.trim().match(/^\((.*) ([\w.\[\]*]+)\)$/s);
  if (!m) return raw;
  const [, v, t] = m;
  if (t === "string") return JSON.parse(v);
  if (t === "bool") return v === "true";
  if (/^u?int\d*$/.test(t)) return Number(v);
  return v;
}

// goLiteral quotes a form value for a qeval expression according to its gno type.
export function goLiteral(value, type) {
  if (type === "string" || type === ".uverse.address" || type === "address") return JSON.stringify(value);
  if (type === "bool") return value === "true" ? "true" : "false";
  if (/^u?int\d*$|^float\d+$/.test(type)) {
    if (!/^-?\d+(\.\d+)?$/.test(value)) throw new Error(`not a number: ${value}`);
    return value;
  }
  throw new Error(`type ${type} cannot be typed into a form`);
}

// isRealmParam reports whether a parameter is the `cur realm` a crossing
// function takes first. Such functions need a transaction, not a query.
export const isRealmParam = (p) => p.Type.includes("IsCurrent func() bool");
