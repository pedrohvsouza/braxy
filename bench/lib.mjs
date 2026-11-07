export const TARGET = process.env.TARGET ?? "http://localhost:3000";
export const ORIGIN = "http://bench.local";

export const pad = (n) => String(n).padStart(5, "0");
export const benchUser = (n) => `bench_${pad(n)}`;

/** Logs a user in; returns {cookie, csrf}. */
export async function login(username, password = "password123") {
  const res = await fetch(`${TARGET}/api/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: ORIGIN },
    body: JSON.stringify({ login: username, password }),
  });
  if (!res.ok) throw new Error(`login ${username}: ${res.status} ${await res.text()}`);
  const jar = {};
  for (const c of res.headers.getSetCookie()) {
    const [pair] = c.split(";");
    const i = pair.indexOf("=");
    jar[pair.slice(0, i)] = pair.slice(i + 1);
  }
  await res.arrayBuffer().catch(() => undefined);
  return {
    cookie: Object.entries(jar).map(([k, v]) => `${k}=${v}`).join("; "),
    csrf: decodeURIComponent(jar.saci_csrf ?? ""),
  };
}

export async function api(session, method, path, body) {
  const res = await fetch(`${TARGET}${path}`, {
    method,
    headers: {
      Cookie: session.cookie,
      "X-CSRF-Token": session.csrf,
      "Content-Type": "application/json",
      Origin: ORIGIN,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

export function percentile(sorted, p) {
  if (!sorted.length) return NaN;
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

export async function pool(items, concurrency, fn) {
  const out = new Array(items.length);
  let i = 0;
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, async () => {
      while (i < items.length) {
        const idx = i++;
        out[idx] = await fn(items[idx], idx);
      }
    }),
  );
  return out;
}
