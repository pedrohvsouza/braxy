// Concurrent users: ramps ChatChannel sockets and measures fan-out latency.
//   node ws.mjs [--steps 1000,2500,5000,10000,15000,20000] [--procs 10]
import { fork } from "node:child_process";
import { api, benchUser, login, percentile, pool } from "./lib.mjs";

const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : def;
};
const STEPS = arg("steps", "500,1000,2000,3000,5000,7500,10000,12500,15000,17500,20000").split(",").map(Number);
const PROCS = Number(arg("procs", 10));
const SETTLE_MS = 8_000;

const workers = Array.from({ length: PROCS }, () => fork(new URL("./ws-worker.mjs", import.meta.url)));
const ask = (w, msg, reply) =>
  new Promise((resolve) => {
    const on = (m) => {
      if (m.type === reply) {
        w.off("message", on);
        resolve(m);
      }
    };
    w.on("message", on);
    w.send(msg);
  });
const all = (msg, reply) => Promise.all(workers.map((w) => ask(w, msg, reply)));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const stamp = () => new Date().toISOString().slice(11, 19);

const sender = await login(benchUser(20000));
const lobby = (await api(sender, "GET", "/api/sidebar")).groups.find((g) => g.kind === "lobby").conversation_id;

// One poster per room (room r's owner is bench user (r-1)*50+1).
const posters = new Map();
async function posterFor(r) {
  if (!posters.has(r)) {
    const s = await login(benchUser((r - 1) * 50 + 1));
    const side = await api(s, "GET", "/api/sidebar");
    posters.set(r, { ...s, room: side.groups.find((g) => g.kind === "group").conversation_id });
  }
  return posters.get(r);
}

async function measure(label, expectedPerMsg, sendRound, rounds) {
  await all({ type: "reset" }, "reset");
  let sent = 0;
  let sendErrors = 0;
  for (let i = 0; i < rounds; i++) {
    const t = Date.now();
    const res = await sendRound(i);
    sent += res.sent;
    sendErrors += res.errors;
    await sleep(Math.max(0, 1000 - (Date.now() - t)));
  }
  await sleep(5000); // let stragglers arrive
  const reports = await all({ type: "report" }, "report");
  const lat = reports.flatMap((r) => r.latencies).sort((a, b) => a - b);
  const delivered = reports.reduce((a, r) => a + r.deliveries, 0);
  const expected = sent * expectedPerMsg;
  return {
    cenário: label,
    "msgs enviadas": sent,
    "erros envio": sendErrors,
    entregas: delivered,
    esperadas: expected,
    "entregue %": expected ? +((100 * delivered) / expected).toFixed(2) : 0,
    "p50 ms": percentile(lat, 50),
    "p95 ms": percentile(lat, 95),
    "p99 ms": percentile(lat, 99),
    "max ms": lat.at(-1) ?? NaN,
  };
}

const results = [];
let connected = 0;
for (const target of STEPS) {
  const users = Array.from({ length: target - connected }, (_, i) => connected + i + 1);
  const shards = workers.map((_, w) => users.filter((_, i) => i % PROCS === w));
  console.log(`[${stamp()}] STEP ${target}: abrindo ${users.length} conexões...`);
  const grown = await Promise.all(workers.map((w, i) => ask(w, { type: "grow", users: shards[i] }, "grown")));
  const open = grown.reduce((a, g) => a + g.open, 0);
  const errors = grown.reduce((a, g) => a + g.connectErrors, 0);
  const rampMs = Math.max(...grown.map((g) => g.ms));
  connected = target;
  console.log(`[${stamp()}]   abertas=${open} erros=${errors} rampa=${(rampMs / 1000).toFixed(1)}s`);
  await sleep(SETTLE_MS);

  // Lobby: everyone is a member, 1 message/s for 5 s -> each fans out to all.
  const lobbyRes = await measure(`lobby (${target} ouvintes)`, open, async (i) => {
    try {
      await api(sender, "POST", `/api/conversations/${lobby}/messages`, { body: `bench|${Date.now()}|${target}-${i}` });
      return { sent: 1, errors: 0 };
    } catch {
      return { sent: 0, errors: 1 };
    }
  }, 5);

  // Rooms: every room with connected members gets 1 message/s for 10 s.
  const activeRooms = Math.floor(target / 50);
  await pool(Array.from({ length: activeRooms }, (_, i) => i + 1), 32, (r) => posterFor(r).catch(() => null));
  const roomRes = await measure(`salas (${activeRooms} salas × 50, ${activeRooms} msg/s)`, 50, async (i) => {
    const outcomes = await pool(Array.from({ length: activeRooms }, (_, k) => k + 1), 64, async (r) => {
      try {
        const p = await posterFor(r);
        await api(p, "POST", `/api/conversations/${p.room}/messages`, { body: `bench|${Date.now()}|r${r}-${i}` });
        return 1;
      } catch {
        return 0;
      }
    });
    const ok = outcomes.reduce((a, b) => a + b, 0);
    return { sent: ok, errors: outcomes.length - ok };
  }, 10);

  // Room deliveries also reach the lobby? No: room messages go only to room
  // members, and each room has exactly 50 connected members at this step.
  const step = { usuários: target, abertas: open, "erros conexão": errors, "rampa s": +(rampMs / 1000).toFixed(1) };
  results.push({ ...step, ...lobbyRes }, { ...step, ...roomRes });
  console.log(`[${stamp()}]   lobby p99=${lobbyRes["p99 ms"]}ms entregue=${lobbyRes["entregue %"]}%  |  salas p99=${roomRes["p99 ms"]}ms entregue=${roomRes["entregue %"]}%`);

  if (errors > target * 0.01 || lobbyRes["entregue %"] < 99 || roomRes["entregue %"] < 99) {
    console.log(`[${stamp()}] parando: falhas acima de 1% neste degrau`);
    break;
  }
}

console.table(results);
console.log("JSON:" + JSON.stringify(results));
workers.forEach((w) => w.send({ type: "exit" }));
await sleep(500);
process.exit(0);
