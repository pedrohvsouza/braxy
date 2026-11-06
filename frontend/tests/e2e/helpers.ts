import { type Browser, expect, type Page } from "@playwright/test";

export const PASSWORD = "password123";

export async function login(page: Page, login: string, password = PASSWORD): Promise<void> {
  await page.goto("/");
  const form = page.getByTestId("signin-form");
  await form.getByPlaceholder("E-mail ou usuário").fill(login);
  await form.getByPlaceholder("Senha").fill(password);
  await form.getByRole("button", { name: "Entrar", exact: true }).click();
  await expect(page.getByPlaceholder("Pesquisar usuário…")).toBeVisible();
}

export async function newSession(browser: Browser, user: string): Promise<Page> {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await login(page, user);
  return page;
}

export function unique(prefix: string): string {
  return `${prefix}${Date.now().toString(36).slice(-6)}${Math.floor(Math.random() * 100)}`;
}

export async function signUp(page: Page, username: string, name = "Visitante Teste"): Promise<void> {
  await page.goto("/");
  await page.getByRole("button", { name: "Cadastre-se" }).click();
  const form = page.getByTestId("signup-form");
  await page.waitForTimeout(650); // slide animation
  await form.getByPlaceholder("Nome de exibição").fill(name);
  await form.getByPlaceholder("Usuário (@)").fill(username);
  await form.getByPlaceholder("E-mail").fill(`${username}@e2e.local`);
  await form.getByPlaceholder("Senha").fill(PASSWORD);
  await form.getByRole("button", { name: "Cadastrar", exact: true }).click();
  await expect(page.getByPlaceholder("Pesquisar usuário…")).toBeVisible();
}

/** Opens the conversation row whose test id starts with the given prefix. */
export async function openLobby(page: Page): Promise<void> {
  await page.locator('[data-testid^="group-"]').filter({ hasText: "Grupo" }).first().click();
  await expect(page.getByTestId("message-list")).toBeVisible();
}
