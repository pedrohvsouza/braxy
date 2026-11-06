import { expect, test } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { login, newSession, openLobby, unique } from "./helpers";

const here = path.dirname(fileURLToPath(import.meta.url));

test("lobby: send, reply, react, edit and delete", async ({ page }) => {
  await login(page, "rafa");
  await openLobby(page);
  const text = unique("Mensagem e2e ");
  await page.getByPlaceholder("Digite sua mensagem…").fill(text);
  await page.keyboard.press("Enter");
  const mine = page.getByTestId("message").filter({ hasText: text }).first();
  await expect(mine).toBeVisible();

  await mine.hover();
  await mine.getByRole("button", { name: "Reagir" }).click();
  await mine.getByRole("button", { name: "🔥" }).click();
  await expect(mine.getByRole("button", { name: "🔥 1" })).toBeVisible();

  await mine.hover();
  await mine.getByRole("button", { name: "Responder" }).click();
  await expect(page.getByText("Respondendo a Rafael Lima")).toBeVisible();
  const reply = unique("resposta ");
  await page.getByPlaceholder("Digite sua mensagem…").fill(reply);
  await page.keyboard.press("Enter");
  const replyMsg = page.getByTestId("message").filter({ hasText: reply });
  await expect(replyMsg.getByRole("button", { name: new RegExp(text) })).toBeVisible();

  await replyMsg.hover();
  await replyMsg.getByRole("button", { name: "Editar" }).click();
  await page.getByPlaceholder("Digite sua mensagem…").fill(`${reply} (corrigida)`);
  await page.keyboard.press("Enter");
  await expect(page.getByTestId("message").filter({ hasText: `${reply} (corrigida)` })).toContainText("editada");

  page.once("dialog", (d) => void d.accept());
  await mine.hover();
  await mine.getByRole("button", { name: "Apagar" }).click();
  await expect(page.getByTestId("message").filter({ hasText: "mensagem apagada" }).first()).toBeVisible();
});

test("image upload shows inline", async ({ page }) => {
  await login(page, "julia");
  await openLobby(page);
  await page.getByTestId("image-input").setInputFiles(path.join(here, "fixtures", "eagle.png"));
  await expect(page.getByTestId("message").last().locator("img[src^='/api/files/']").last()).toBeVisible();
});

test("realtime DM between two browsers: message, typing, seen", async ({ browser }) => {
  const pedro = await newSession(browser, "pedro");
  const marina = await newSession(browser, "marina");

  await pedro.getByTestId("friend-marina").click();
  await marina.getByTestId("friend-pedro").click();
  await expect(marina.getByTestId("message-list")).toBeVisible();

  await pedro.getByPlaceholder("Digite sua mensagem…").pressSequentially("oi", { delay: 30 });
  await expect(marina.getByText("Pedro Henrique está digitando…").last()).toBeVisible();

  const text = unique("ao vivo ");
  await pedro.getByPlaceholder("Digite sua mensagem…").fill(text);
  await pedro.keyboard.press("Enter");
  await expect(marina.getByTestId("message").filter({ hasText: text })).toBeVisible();
  await expect(pedro.getByTestId("message").filter({ hasText: text }).getByText("Visto")).toBeVisible();

  await pedro.context().close();
  await marina.context().close();
});

test("friend request, notification and DM", async ({ browser }) => {
  const nameA = unique("amigo_a");
  const a = await browser.newContext().then((c) => c.newPage());
  const { signUp } = await import("./helpers");
  await signUp(a, nameA, "Amigo A");

  const thiago = await newSession(browser, "thiago");
  await a.getByPlaceholder("Pesquisar usuário…").fill("thiago");
  await a.getByTestId("search-thiago").getByRole("button", { name: "Adicionar" }).click();
  await expect(a.getByTestId("search-thiago").getByRole("button", { name: "Pendente" })).toBeVisible();

  await expect(thiago.getByTestId("toast").filter({ hasText: "pedido de amizade" })).toBeVisible();
  await expect(thiago.getByTestId("bell-count")).toBeVisible();
  await thiago.getByRole("button", { name: /Pedidos de amizade/ }).click();
  await thiago.getByTestId(`request-${nameA}`).getByRole("button", { name: "Aceitar" }).click();
  await thiago.keyboard.press("Escape");

  await expect(a.getByTestId("toast").filter({ hasText: "aceitou" })).toBeVisible();
  await a.getByPlaceholder("Pesquisar usuário…").fill("");
  await a.getByTestId("friend-thiago").click();
  await a.getByPlaceholder("Digite sua mensagem…").fill("valeu por aceitar!");
  await a.keyboard.press("Enter");
  await expect(thiago.getByTestId(`friend-${nameA}`)).toContainText("valeu por aceitar!");

  await a.context().close();
  await thiago.context().close();
});

test("create a group with a friend and mention them", async ({ browser }) => {
  const pedro = await newSession(browser, "pedro");
  const julia = await newSession(browser, "julia");
  const group = unique("Grupo e2e ");

  await pedro.getByRole("button", { name: "Criar" }).click();
  await pedro.getByRole("menuitem", { name: "Criar grupo" }).click();
  await pedro.getByLabel("Nome do grupo").fill(group);
  await pedro.getByTestId("pick-julia").check();
  await pedro.getByRole("button", { name: "Criar grupo" }).click();
  await expect(pedro.getByRole("banner").getByText(group).or(pedro.locator("header strong", { hasText: group }))).toBeVisible();

  await expect(julia.getByTestId("toast").filter({ hasText: group })).toBeVisible();
  await pedro.getByPlaceholder("Digite sua mensagem…").fill("@julia bem-vinda!");
  await pedro.keyboard.press("Enter");
  await expect(julia.getByTestId("toast").filter({ hasText: "mencionou você" })).toBeVisible();

  await pedro.context().close();
  await julia.context().close();
});
