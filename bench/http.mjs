// HTTP throughput: autocannon against the main endpoints.
//   node http.mjs [--duration 20] [--connections 64]
import autocannon from "autocannon";
import { api, benchUser, login, pool, TARGET } from "./lib.mjs";

const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? Number(process.argv[i + 1]) : def;
};
const DURATION = arg("duration", 20);
const CONNECTIONS = arg("connections", 64);
const WORKERS = arg("workers", 4);

const main = await login(benchUser(1));
const sidebar = await api(main, "GET", "/api/sidebar");
const room = sidebar.groups.find((g) => g.kind === "group");
// Make sure the history endpoint returns a full page.
const page = await api(main, "GET", `/api/conversations/${room.conversation_id}/messages`);
for (let i = page.messages.length; i < 60; i++) {
  await api(main, "POST", `/api/conversations/${room.conversation_id}/messages`, { body: `histórico ${i}` });
}

// 400 posters, one per room, so writes spread over rooms like real traffic.
const posters = await pool(Array.from({ length: 400 }, (_, r) => r * 50 + 1), 32, async (n) => {
  const s = await login(benchUser(n));
  const side = await api(s, "GET", "/api/sidebar");
  return { ...s, room: side.groups.find((g) => g.kind === "group").conversation_id };
});

const authHeaders = { cookie: main.cookie, "x-csrf-token": main.csrf, origin: "http://bench.local" };

const scenarios = [
  { name: "GET /up (sem auth, sem DB)", path: "/up" },
  { name: "GET /api/session (cookie + 1 query)", path: "/api/session", headers: authHeaders },
  { name: "GET /api/stats (4 COUNTs)", path: "/api/stats", headers: authHeaders },
  { name: "GET /api/sidebar (agregação)", path: "/api/sidebar", headers: authHeaders },
  { name: "GET messages (página de 50)", path: `/api/conversations/${room.conversation_id}/messages`, headers: authHeaders },
  {
    name: "POST message (400 salas, broadcast)",
    method: "POST",
    path: "/",
    setupRequest: (req) => {
      const p = posters[Math.floor(Math.random() * posters.length)];
      return {
        ...req,
        path: `/api/conversations/${p.room}/messages`,
        headers: {
          "content-type": "application/json",
          cookie: p.cookie,
          "x-csrf-token": p.csrf,
          origin: "http://bench.local",
        },
        body: JSON.stringify({ body: "carga 🚀 @bench_00001" }),
      };
    },
  },
];

const rows = [];
for (const s of scenarios) {
  const opts = {
    url: TARGET,
    duration: DURATION,
    connections: CONNECTIONS,
    workers: s.setupRequest ? 0 : WORKERS, // setupRequest closures can't cross worker threads
    method: s.method ?? "GET",
    headers: s.headers,
    requests: [{ method: s.method ?? "GET", path: s.path, ...(s.setupRequest ? { setupRequest: s.setupRequest } : {}) }],
  };
  process.stdout.write(`→ ${s.name} ... `);
  const r = await autocannon(opts);
  const row = {
    cenário: s.name,
    "req/s (média)": Math.round(r.requests.average),
    "req/s (pico)": r.requests.max,
    "p50 ms": r.latency.p50,
    "p99 ms": r.latency.p99,
    "max ms": r.latency.max,
    total: r.requests.total,
    erros: r.errors + r.timeouts,
    "não-2xx": r.non2xx,
  };
  rows.push(row);
  console.log(`${row["req/s (média)"]} req/s, p99 ${row["p99 ms"]} ms`);
  await new Promise((res) => setTimeout(res, 3000));
}
console.log(`\nHTTP — ${CONNECTIONS} conexões, ${DURATION}s por cenário`);
console.table(rows);
console.log("JSON:" + JSON.stringify(rows));
