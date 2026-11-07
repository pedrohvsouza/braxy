// Read-after-write check across backend processes: posts a message, then
// immediately reads the conversation's latest page and the sidebar on a
// fresh connection (SO_REUSEPORT spreads those over every process), and
// counts reads that do not show the new message yet. Optional background
// load (--load N concurrent posters) keeps the processes busy meanwhile.
//   node consistency.mjs [--rounds 500] [--load 0]
import http from "node:http";
import { benchUser, login, ORIGIN, TARGET } from "./lib.mjs";

const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? Number(process.argv[i + 1]) : def;
};
const ROUNDS = arg("rounds", 500);
const LOAD = arg("load", 0);
const url = new URL(TARGET);

// One request on its own TCP connection (no keep-alive agent).
function request(session, method, path, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: url.hostname, port: url.port, method, path, agent: false,
        headers: { Cookie: session.cookie, "X-CSRF-Token": session.csrf, "Content-Type": "application/json", Origin: ORIGIN, Connection: "close" },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => (res.statusCode < 300 ? resolve(JSON.parse(data)) : reject(new Error(`${method} ${path}: ${res.statusCode}`))));
      },
    );
    req.on("error", reject);
    if (body !== undefined) req.write(JSON.stringify(body));
    req.end();
  });
}

const me = await login(benchUser(1));
const sidebar = await request(me, "GET", "/api/sidebar");
const entries = (side) => [...(side.groups ?? []), ...(side.friends ?? [])];
const cid = entries(sidebar).find((c) => c.kind === "group")?.conversation_id;
if (!cid) throw new Error(`no conversation in sidebar: ${JSON.stringify(sidebar).slice(0, 200)}`);

let stop = false;
const loaders = [];
for (let i = 0; i < LOAD; i++) {
  const s = await login(benchUser(100 + i));
  loaders.push((async () => {
    while (!stop) await request(s, "POST", `/api/conversations/${cid}/messages`, { body: "carga" }).catch(() => {});
  })());
}

let pageMisses = 0, sidebarMisses = 0;
for (let r = 0; r < ROUNDS; r++) {
  const body = `consistency-${Date.now()}-${r}`;
  const posted = await request(me, "POST", `/api/conversations/${cid}/messages`, { body });
  const id = posted.message.id;
  const [page, side] = await Promise.all([
    request(me, "GET", `/api/conversations/${cid}/messages`),
    request(me, "GET", "/api/sidebar"),
  ]);
  if (!page.messages.some((m) => m.id >= id)) pageMisses++;
  const entry = entries(side).find((c) => c.conversation_id === cid);
  if (!(entry?.last_message?.id >= id)) sidebarMisses++;
}
stop = true;
await Promise.all(loaders);
console.log(JSON.stringify({ rounds: ROUNDS, load: LOAD, page_misses: pageMisses, sidebar_misses: sidebarMisses }));
