import react from "@vitejs/plugin-react";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { defineConfig } from "vitest/config";

const pkg = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")) as { version: string };

function gitSha(): string {
  if (process.env.BRAXY_GIT_SHA) return process.env.BRAXY_GIT_SHA;
  try {
    return execSync("git rev-parse --short HEAD", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
  } catch {
    return "dev";
  }
}

const target = process.env.VITE_PROXY_TARGET ?? "http://localhost:3000";

// Same-origin in dev: Vite proxies the API and the WebSocket, so the HttpOnly
// session cookie and the CSRF cookie behave exactly like production.
export default defineConfig({
  plugins: [react()],
  define: {
    __APP_VERSION__: JSON.stringify(`v${pkg.version}+${gitSha()}`),
  },
  server: {
    proxy: {
      "/api": { target },
      "/up": { target },
      "/cable": { target: target.replace(/^http/, "ws"), ws: true },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test-setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
  },
});
