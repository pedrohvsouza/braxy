import { expect, test } from "@playwright/test";
import { login, openLobby, unique } from "./helpers";

test("earned badges show on the profile and locked ones stay grey", async ({ page }) => {
  await login(page, "pedro");
  await openLobby(page);
  // Any XP change runs the check (pedro is level 33 with friends).
  await page.getByPlaceholder("Digite sua mensagem…").fill(unique("conquista "));
  await page.keyboard.press("Enter");

  await expect(async () => {
    await page.getByRole("button", { name: "Meu perfil" }).click();
    await page.getByRole("menuitem", { name: "Meu perfil" }).click();
    const card = page.getByTestId("profile-card");
    try {
      await expect(card.getByTestId("badge-level_25")).toHaveClass(/badgeOn/, { timeout: 1000 });
    } finally {
      await page.keyboard.press("Escape");
    }
  }).toPass({ timeout: 15_000 });

  await page.getByRole("button", { name: "Meu perfil" }).click();
  await page.getByRole("menuitem", { name: "Meu perfil" }).click();
  const card = page.getByTestId("profile-card");
  await expect(card.getByTestId("badge-first_friend")).toHaveClass(/badgeOn/);
  await expect(card.getByTestId("badge-level_50")).toHaveClass(/badgeOff/);
  await expect(card.getByRole("heading", { name: /Conquistas · \d+\/11/ })).toBeVisible();
});
