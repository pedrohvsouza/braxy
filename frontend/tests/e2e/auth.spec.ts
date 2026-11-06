import { expect, test } from "@playwright/test";
import { login, signUp, unique } from "./helpers";

test("auth card slides between sign in and sign up", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("[data-mode]");
  await expect(card).toHaveAttribute("data-mode", "signin");
  await expect(page.getByRole("heading", { name: "Entrar no Braxy" })).toBeVisible();
  await page.getByRole("button", { name: "Cadastre-se" }).click();
  await expect(card).toHaveAttribute("data-mode", "signup");
  await page.waitForTimeout(700); // let the 0.6s slide finish
  await expect(page.getByRole("heading", { name: "Criar conta" })).toBeVisible();
  await page.getByRole("button", { name: "Já tenho conta" }).click();
  await expect(card).toHaveAttribute("data-mode", "signin");
});

test("wrong password shows an error", async ({ page }) => {
  await page.goto("/");
  const form = page.getByTestId("signin-form");
  await form.getByPlaceholder("E-mail ou usuário").fill("pedro");
  await form.getByPlaceholder("Senha").fill("errada123");
  await form.getByRole("button", { name: "Entrar", exact: true }).click();
  await expect(form.getByRole("alert")).toContainText("incorretos");
});

test("sign up lands in the app with the lobby and live stats", async ({ page }) => {
  const username = unique("e2e_");
  await signUp(page, username);
  await expect(page.locator('[data-testid^="group-"]').filter({ hasText: "Grupo" })).toBeVisible();
  await expect(page.getByTestId("stat-users")).not.toContainText("—");
  await expect(page.getByTestId("latency")).toContainText("ms de latência");
  await expect(page.getByTestId("xp-text")).toContainText("para o nível 3");
  await expect(page.locator("footer")).toContainText("Feito usando Saci");
});

test("logout returns to the auth card", async ({ page }) => {
  await login(page, "julia");
  await page.getByRole("button", { name: "Meu perfil" }).first().click();
  await page.getByRole("menuitem", { name: "Sair" }).click();
  await expect(page.getByRole("heading", { name: "Entrar no Braxy" })).toBeVisible();
});
