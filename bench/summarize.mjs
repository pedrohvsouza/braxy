// Builds the chart datasets from the raw benchmark outputs.
//   node summarize.mjs  -> results/http_sweep.json, results/ws_ramp.json
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const json = (file) => {
  const line = readFileSync(file, "utf8").split("\n").find((l) => l.startsWith("JSON:"));
  return line ? JSON.parse(line.slice(5)) : null;
};

// A run that died before printing JSON: rebuild rows from progress lines.
function fromProgress(text) {
  const rows = [];
  const re = /STEP (\d+):[^\n]*\n[^\n]*abertas=(\d+) erros=(\d+) rampa=([\d.]+)s(?:\n[^\n]*lobby p99=(\w+)ms entregue=([\d.]+)%\s+\|\s+salas p99=(\w+)ms entregue=([\d.]+)%)?/g;
  for (const m of text.matchAll(re)) {
    const base = { "usuários": +m[1], abertas: +m[2], "erros conexão": +m[3], "rampa s": +m[4] };
    const n = (v) => (v === undefined || v === "NaN" ? null : +v);
    rows.push({ ...base, "cenário": "lobby", "entregue %": n(m[6]) ?? 0, "p99 ms": n(m[5]), "msgs enviadas": null });
    rows.push({ ...base, "cenário": "salas", "entregue %": n(m[8]) ?? 0, "p99 ms": n(m[7]), "msgs enviadas": null });
  }
  return rows;
}

// Peak backend memory/CPU between two HH:MM:SS marks of docker-stats.csv.
// Older samples were stamped in host local time; BENCH_TZ_OFFSET (hours to
// add to reach UTC, e.g. 3 for UTC-3) normalizes them. New ones are UTC.
const OFFSET = Number(process.env.BENCH_TZ_OFFSET ?? 0);
const toUtc = (hms) => {
  if (!OFFSET) return hms;
  const [h, m, s] = hms.split(":").map(Number);
  const t = ((h + OFFSET + 24) % 24) * 3600 + m * 60 + s;
  return [Math.floor(t / 3600), Math.floor((t % 3600) / 60), t % 60].map((n) => String(n).padStart(2, "0")).join(":");
};

function stats(file) {
  if (!existsSync(file)) return [];
  return readFileSync(file, "utf8").trim().split("\n").slice(1).map((l) => {
    const [time, name, cpu, mem] = l.split(",");
    const used = mem.split("/")[0].trim();
    const mib = used.endsWith("GiB") ? parseFloat(used) * 1024 : used.endsWith("KiB") ? parseFloat(used) / 1024 : parseFloat(used);
    return { time: toUtc(time), name, cpu: parseFloat(cpu), mib };
  });
}

const http = [];
for (const [config, file] of [["MT (4 workers)", "results/http-sweep-mt.txt"], ["ST (1 thread)", "results/http-sweep-st.txt"]]) {
  if (!existsSync(file)) continue;
  for (const p of json(file) ?? []) http.push({ config, ...p });
}
writeFileSync("results/http_sweep.json", JSON.stringify(http, null, 1));

const ws = [];
for (const [config, file, statsFile] of [
  ["MT (4 workers)", "results/ws-mt.txt", "results/ws-mt-stats.csv"],
  ["ST (1 thread)", "results/ws-st.txt", "results/ws-st-stats.csv"],
]) {
  if (!existsSync(file)) continue;
  const text = readFileSync(file, "utf8");
  // "[HH:MM:SS] STEP n:" marks where each step starts.
  const marks = [...text.matchAll(/\[(\d\d:\d\d:\d\d)\] STEP (\d+):/g)].map((m) => ({ t: m[1], users: +m[2] }));
  const samples = stats(statsFile).filter((s) => s.name.includes("backend"));
  const pg = stats(statsFile).filter((s) => s.name.includes("pg"));
  for (const row of json(file) ?? fromProgress(text)) {
    const i = marks.findIndex((m) => m.users === row["usuários"]);
    const from = marks[i]?.t ?? "00:00:00";
    const to = marks[i + 1]?.t ?? "99:99:99";
    const inStep = (s) => s.time >= from && s.time < to;
    const b = samples.filter(inStep);
    const p = pg.filter(inStep);
    ws.push({
      config,
      users: row["usuários"],
      open: row.abertas,
      connect_errors: row["erros conexão"],
      ramp_s: row["rampa s"],
      scenario: row["cenário"].startsWith("lobby") ? "lobby" : "salas",
      sent: row["msgs enviadas"],
      delivered_pct: row["entregue %"],
      p50: row["p50 ms"] ?? null,
      p95: row["p95 ms"] ?? null,
      p99: row["p99 ms"],
      max: row["max ms"] ?? null,
      backend_mib: b.length ? Math.round(Math.max(...b.map((s) => s.mib))) : null,
      backend_cpu: b.length ? Math.round(Math.max(...b.map((s) => s.cpu))) : null,
      pg_cpu: p.length ? Math.round(Math.max(...p.map((s) => s.cpu))) : null,
    });
  }
}
writeFileSync("results/ws_ramp.json", JSON.stringify(ws, null, 1));
console.log(`http points: ${http.length}, ws rows: ${ws.length}`);
