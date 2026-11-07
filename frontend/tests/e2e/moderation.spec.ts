import { expect, test } from "@playwright/test";
import { newSession, openLobby, unique } from "./helpers";

test("a moderator mutes from a message and lifts it from the sanction list", async ({ browser }) => {
  const rafa = await newSession(browser, "rafa"); // moderator
  const thiago = await newSession(browser, "thiago");
  await openLobby(rafa);
  await openLobby(thiago);

  const text = unique("modera ");
  await thiago.getByPlaceholder("Digite sua mensagem…").fill(text);
  await thiago.keyboard.press("Enter");
  const msg = rafa.getByTestId("message").filter({ hasText: text });
  await msg.hover();
  await msg.getByRole("button", { name: "Moderar" }).click();
  await rafa.getByTestId("moderate-modal").getByRole("button", { name: "10 minutos" }).click();

  // Thiago's composer locks live (conversation.updated over the socket).
  await expect(thiago.getByPlaceholder(/Você está silenciado nesta conversa até/)).toBeDisabled();

  await rafa.getByRole("button", { name: "Informações" }).click();
  const list = rafa.getByTestId("sanction-list");
  await expect(list).toContainText("Thiago");
  await list.getByRole("button", { name: "Desfazer" }).click();
  await expect(list).toContainText("Nenhuma sanção ativa.");
  await expect(thiago.getByPlaceholder("Digite sua mensagem…")).toBeEnabled();

  await rafa.context().close();
  await thiago.context().close();
});

test("blocking collapses the other's messages and is undone from settings", async ({ browser }) => {
  const julia = await newSession(browser, "julia");
  const thiago = await newSession(browser, "thiago");
  await openLobby(julia);
  await openLobby(thiago);

  const hello = unique("oi ");
  await thiago.getByPlaceholder("Digite sua mensagem…").fill(hello);
  await thiago.keyboard.press("Enter");
  await julia.getByTestId("message").filter({ hasText: hello }).getByRole("button", { name: "Thiago Rocha" }).first().click();
  julia.once("dialog", (d) => void d.accept());
  await julia.getByTestId("block-toggle").click();
  await expect(julia.getByTestId("block-toggle")).toHaveText("Desbloquear");
  await julia.keyboard.press("Escape");

  const text = unique("bloqueado ");
  await thiago.getByPlaceholder("Digite sua mensagem…").fill(text);
  await thiago.keyboard.press("Enter");
  const hidden = julia.getByTestId("message").filter({ hasText: "Mensagem de um usuário bloqueado." }).last();
  await expect(hidden).toBeVisible();
  await hidden.getByRole("button", { name: "Mostrar" }).click();
  await expect(julia.getByTestId("message").filter({ hasText: text })).toBeVisible();

  await julia.getByRole("button", { name: "Configurações" }).first().click();
  await julia.getByRole("tab", { name: "Bloqueados" }).click();
  const blocked = julia.getByTestId("blocked-list");
  await blocked.getByRole("button", { name: "Desbloquear" }).click();
  await expect(julia.getByText("Você não bloqueou ninguém.")).toBeVisible();

  await julia.context().close();
  await thiago.context().close();
});
