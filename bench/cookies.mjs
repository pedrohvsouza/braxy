// Logs N bench users in and writes their session cookies for wrk:
//   node cookies.mjs [N] > results/cookies.tsv   (cookie<TAB>csrf<TAB>room id per line)
import { api, benchUser, login, pool } from "./lib.mjs";

const n = Number(process.argv[2] ?? 2000);
const rows = await pool(Array.from({ length: n }, (_, i) => i + 1), 50, async (k) => {
  const s = await login(benchUser(k));
  const side = await api(s, "GET", "/api/sidebar");
  const room = side.groups.find((g) => g.kind === "group").conversation_id;
  return `${s.cookie}\t${s.csrf}\t${room}`;
});
process.stdout.write(rows.join("\n") + "\n");
