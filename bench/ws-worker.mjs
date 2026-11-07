// One load-generator process: logs users in, keeps their ChatChannel
// sockets open and measures message delivery latency.
import WebSocket from "ws";
import { benchUser, login, ORIGIN, pool, TARGET } from "./lib.mjs";

const WS_URL = TARGET.replace(/^http/, "ws") + "/cable";
const IDENT = JSON.stringify({ channel: "ChatChannel" });
const sockets = [];
let latencies = [];
let deliveries = 0;
let connectErrors = 0;
let dropped = 0;

function open(n) {
  return new Promise((resolve) => {
    login(benchUser(n))
      .then((s) => {
        const ws = new WebSocket(WS_URL, { headers: { Cookie: s.cookie, Origin: ORIGIN }, perMessageDeflate: false, handshakeTimeout: 30_000 });
        let done = false;
        const finish = (ok) => {
          if (done) return;
          done = true;
          if (!ok) connectErrors++;
          resolve(ok);
        };
        const timer = setTimeout(() => {
          finish(false);
          ws.terminate();
        }, 60_000);
        ws.on("message", (raw) => {
          const frame = JSON.parse(raw);
          if (frame.type === "welcome") ws.send(JSON.stringify({ command: "subscribe", identifier: IDENT }));
          else if (frame.type === "confirm_subscription") {
            clearTimeout(timer);
            sockets.push(ws);
            finish(true);
          } else if (frame.message?.type === "message.created") {
            const body = frame.message.message.body;
            if (body.startsWith("bench|")) {
              latencies.push(Date.now() - Number(body.split("|")[1]));
              deliveries++;
            }
          }
        });
        ws.on("error", () => {
          clearTimeout(timer);
          finish(false);
        });
        ws.on("close", () => {
          if (done) dropped++;
          clearTimeout(timer);
          finish(false);
        });
      })
      .catch(() => {
        connectErrors++;
        resolve(false);
      });
  });
}

// Heartbeats like the real client (every 30s, jittered).
setInterval(() => {
  const hb = JSON.stringify({ command: "message", identifier: IDENT, data: JSON.stringify({ action: "heartbeat" }) });
  for (const ws of sockets) if (ws.readyState === 1 && Math.random() < 0.5) ws.send(hb);
}, 15_000);

process.on("message", async (cmd) => {
  if (cmd.type === "grow") {
    const t0 = Date.now();
    await pool(cmd.users, 40, (n) => open(n));
    process.send({ type: "grown", open: sockets.filter((w) => w.readyState === 1).length, connectErrors, ms: Date.now() - t0 });
  } else if (cmd.type === "reset") {
    latencies = [];
    deliveries = 0;
    process.send({ type: "reset" });
  } else if (cmd.type === "report") {
    process.send({ type: "report", latencies, deliveries, open: sockets.filter((w) => w.readyState === 1).length, dropped });
  } else if (cmd.type === "exit") {
    for (const ws of sockets) ws.terminate();
    process.exit(0);
  }
});
