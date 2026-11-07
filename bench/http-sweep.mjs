// HTTP concurrency sweep: for each endpoint, raise concurrent connections
// step by step and record throughput + latency at each level.
//   node http-sweep.mjs [--duration 10] [--levels 8,16,32,64,128,256,512]
import autocannon from "autocannon";
import { api, benchUser, login, pool, TARGET } from "./lib.mjs";

const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : def;
};
const DURATION = Number(arg("duration", 10));
const LEVELS = arg("levels", "8,16,32,64,128,256,512").split(",").map(Number);

const main = await login(benchUser(1));
const room = (await api(main, "GET", "/api/sidebar")).groups.find((g) => g.kind === "group").conversation_id;
const posters = await pool(Array.from({ length: 400 }, (_, r) => r * 50 + 1), 32, async (n) => {
  const s = await login(benchUser(n));
  const side = await api(s, "GET", "/api/sidebar");
  return { ...s, room: side.groups.find((g) => g.kind === "group").conversation_id };
});
const auth = { cookie: main.cookie, "x-csrf-token": main.csrf, origin: "http://bench.local" };

const endpoints = [
  { key: "up", name: "GET /up", path: "/up" },
  { key: "session", name: "GET /api/session", path: "/api/session", headers: auth },
  { key: "sidebar", name: "GET /api/sidebar", path: "/api/sidebar", headers: auth },
  { key: "messages", name: "GET messages", path: `/api/conversations/${room}/messages`, headers: auth },
  {
    key: "post",
    name: "POST message",
    method: "POST",
    path: "/",
    setupRequest: (req) => {
      const p = posters[Math.floor(Math.random() * posters.length)];
      return {
        ...req,
        path: `/api/conversations/${p.room}/messages`,
        headers: { "content-type": "application/json", cookie: p.cookie, "x-csrf-token": p.csrf, origin: "http://bench.local" },
        body: JSON.stringify({ body: "carga" }),
      };
    },
  },
];

const points = [];
for (const e of endpoints) {
  for (const c of LEVELS) {
    const r = await autocannon({
      url: TARGET,
      duration: DURATION,
      connections: c,
      workers: e.setupRequest ? 0 : 4,
      headers: e.headers,
      requests: [{ method: e.method ?? "GET", path: e.path, ...(e.setupRequest ? { setupRequest: e.setupRequest } : {}) }],
    });
    const pt = {
      endpoint: e.key,
      name: e.name,
      connections: c,
      rps: Math.round(r.requests.average),
      p50: r.latency.p50,
      p90: r.latency.p90,
      p99: r.latency.p99,
      errors: r.errors + r.timeouts,
      non2xx: r.non2xx,
    };
    points.push(pt);
    console.log(`${e.name.padEnd(18)} c=${String(c).padStart(4)}  ${String(pt.rps).padStart(6)} req/s  p50=${pt.p50}ms p99=${pt.p99}ms err=${pt.errors} non2xx=${pt.non2xx}`);
    await new Promise((res) => setTimeout(res, 2000));
  }
}
console.log("JSON:" + JSON.stringify(points));
