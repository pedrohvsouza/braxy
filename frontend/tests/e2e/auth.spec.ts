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

test("forgot password asks for the email and answers the same for any address", async ({ page }) => {
  // The request is rate limited per address (5 per 15 min); the API itself is
  // covered by the backend spec, so the UI gets a canned answer here.
  await page.route("**/api/password_resets", (route) => route.fulfill({ json: { ok: true } }));
  await page.goto("/");
  await page.getByRole("button", { name: "Esqueceu sua senha?" }).click();
  const form = page.getByTestId("forgot-form");
  await form.getByPlaceholder("E-mail").fill("ninguem@e2e.local");
  await form.getByRole("button", { name: "Enviar link" }).click();
  await expect(form).toContainText("Se existir uma conta com esse e-mail");
  await form.getByRole("button", { name: "Voltar para o login" }).click();
  await expect(page.getByTestId("signin-form")).toBeVisible();
});

test("a bad reset link explains itself and leads back to sign in", async ({ page }) => {
  await page.goto("/reset-password?token=nao-existe");
  await expect(page.getByTestId("reset-page")).toContainText("Link inválido ou expirado");
  await page.getByRole("button", { name: "Voltar para o login" }).click();
  await expect(page.getByTestId("signin-form")).toBeVisible();
});
