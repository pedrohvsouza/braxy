import { expect, test } from "@playwright/test";
import { login } from "./helpers";

interface PageGlobals {
  Notification: { permission: string };
  navigator: {
    serviceWorker: {
      register: (url: string, opts: { scope: string }) => Promise<unknown>;
      getRegistration: (scope: string) => Promise<{ active: { state: string } | null } | undefined>;
    };
  };
}

// Headless Chromium has no push service and reports notification permission
// as denied, so this covers what can run here: the option, its guard and the
// worker itself. Delivery is covered by the backend spec (VAPID signing).
test("push option follows the server key and the service worker installs", async ({ page }) => {
  const key = (await (await page.request.get("/api/push/key")).json()) as { key: string | null };
  test.skip(!key.key, "backend without VAPID_* keys");

  await login(page, "julia");
  await page.getByRole("button", { name: "Configurações" }).first().click();
  await page.getByRole("tab", { name: "Preferências" }).click();
  const push = page.getByLabel(/mesmo com o Braxy fechado/);
  await expect(push).toBeVisible();
  // (Runs in the page; the e2e tsconfig has no DOM types, hence the casts.)
  const permission = await page.evaluate(() => (globalThis as unknown as PageGlobals).Notification.permission);
  if (permission === "denied") await expect(push).toBeDisabled();

  await page.evaluate(() => (globalThis as unknown as PageGlobals).navigator.serviceWorker.register("/sw.js", { scope: "/" }));
  await expect
    .poll(() =>
      page.evaluate(async () => {
        const reg = await (globalThis as unknown as PageGlobals).navigator.serviceWorker.getRegistration("/");
        return reg?.active?.state ?? null;
      }),
    )
    .toBe("activated");
});
