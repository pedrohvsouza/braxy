import { expect, test } from "@playwright/test";
import { login } from "./helpers";

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
  const permission = await page.evaluate(() => Notification.permission);
  if (permission === "denied") await expect(push).toBeDisabled();

  const state = await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.register("/sw.js", { scope: "/" });
    await navigator.serviceWorker.ready;
    return reg.active?.state;
  });
  expect(state).toBe("activated");
});
