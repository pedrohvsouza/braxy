import { expect, test } from "@playwright/test";

test("waits for a backend that is still starting and recovers by itself", async ({ page }) => {
  let failures = 2;
  await page.route("**/api/session", async (route) => {
    if (failures > 0) {
      failures -= 1;
      await route.fulfill({ status: 502, body: "Bad Gateway" });
    } else {
      await route.continue();
    }
  });
  await page.goto("/");
  await expect(page.getByTestId("server-starting")).toContainText("O servidor está iniciando…");
  // Polled every 3 s: the sign-in card shows up with no click.
  await expect(page.getByRole("heading", { name: "Entrar no Braxy" })).toBeVisible({ timeout: 15_000 });
  expect(failures).toBe(0);
});
