// Credential-free Postgres connectivity probe for Laravel Cloud deploys.
// Prints DNS, TCP, SSLRequest/TLS results, then the real driver error chain.
import dns from "node:dns/promises";
import net from "node:net";
import tls from "node:tls";
import util from "node:util";

const raw = process.env.ARTIFACT_SERVER_DATABASE_URL ?? "";
const log = (...a) => console.log("[db-probe]", ...a);
let url;
try { url = new URL(raw); } catch { log("unparseable url"); process.exit(0); }
const secret = decodeURIComponent(url.password || "");
const scrub = (s) => (secret ? String(s).split(secret).join("***") : String(s));
const host = url.hostname;
const port = Number(url.port || 5432);
log("host", host, "port", port, "db", url.pathname, "user-len", url.username.length,
  "params", [...url.searchParams.keys()].join(","));

try {
  const addrs = await dns.lookup(host, {all: true});
  log("dns", JSON.stringify(addrs));
} catch (e) { log("dns error", e.code, e.message); }

const step = (name, fn) => new Promise((resolve) => {
  const t = setTimeout(() => { log(name, "TIMEOUT 8s"); resolve(null); }, 8000);
  fn((v) => { clearTimeout(t); resolve(v); });
});

const sock = await step("tcp", (done) => {
  const s = net.connect({host, port});
  s.once("connect", () => { log("tcp ok", s.remoteAddress, s.remoteFamily); done(s); });
  s.once("error", (e) => { log("tcp error", e.code, e.message); done(null); });
});
if (sock) {
  const reply = await step("sslrequest", (done) => {
    const b = Buffer.alloc(8); b.writeInt32BE(8, 0); b.writeInt32BE(80877103, 4);
    sock.once("data", (d) => done(d.toString("latin1", 0, 1)));
    sock.once("error", (e) => { log("sslrequest error", e.code); done(null); });
    sock.write(b);
  });
  log("sslrequest reply", JSON.stringify(reply));
  if (reply === "S") {
    await step("tls", (done) => {
      const t = tls.connect({socket: sock, servername: process.env.ARTIFACT_SERVER_DATABASE_TLS_SERVERNAME || host});
      t.once("secureConnect", () => { log("tls ok", t.getProtocol(), "authorized", t.authorized, t.authorizationError ?? ""); t.destroy(); done(true); });
      t.once("error", (e) => { log("tls error", e.code, e.message); done(null); });
    });
  } else sock.destroy();
}

try {
  const {PostgresDatabase} = await import("../../dist/storage/postgres-database.js");
  const {Redacted} = await import("effect");
  const db = await PostgresDatabase.inspect({url: Redacted.make(raw), applicationName: "db-probe"});
  log("driver ok");
  await db.close();
} catch (e) {
  log("driver error", scrub(util.inspect(e, {depth: 8, breakLength: 200})));
}
