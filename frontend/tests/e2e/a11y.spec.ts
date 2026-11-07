import { expect, test } from "@playwright/test";
import { login, openLobby, unique } from "./helpers";

test("menus, modals and reactions work from the keyboard", async ({ page }) => {
  await login(page, "julia");
  await openLobby(page);

  // Dropdown: Enter opens on the first item, arrows move, Escape returns focus.
  const create = page.getByRole("button", { name: "Criar" });
  await create.focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("menuitem", { name: "Criar grupo" })).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(page.getByRole("menuitem", { name: "Adicionar amigo" })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(create).toBeFocused();

  // Modal: focus goes in and comes back to the opener.
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter"); // "Criar grupo"
  const dialog = page.getByRole("dialog", { name: "Criar grupo" });
  await expect(dialog.getByPlaceholder(/nome/i).or(dialog.getByRole("textbox").first())).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();

  // Reactions: reachable and named.
  const text = unique("teclado ");
  await page.getByPlaceholder("Digite sua mensagem…").fill(text);
  await page.keyboard.press("Enter");
  const mine = page.getByTestId("message").filter({ hasText: text });
  await mine.getByRole("button", { name: "Reagir" }).focus();
  await page.keyboard.press("Enter");
  await expect(mine.getByRole("menuitem", { name: "Curtir" })).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("Enter"); // "Amei"
  await expect(mine.getByRole("button", { name: "Amei: 1" })).toHaveAttribute("aria-pressed", "true");
});
