import { expect, test } from "@playwright/test";
import { login, openLobby } from "./helpers";

test("lobby members are paged and searchable", async ({ page }) => {
  // A fresh database has a handful of members; pretend the lobby is huge so
  // the search box shows. Searching and paging still hit the real API.
  await page.route(/\/api\/conversations\/\d+$/, async (route) => {
    const res = await route.fetch();
    const body = (await res.json()) as { conversation: { member_count: number } };
    body.conversation.member_count = Math.max(body.conversation.member_count, 60_000);
    await route.fulfill({ response: res, json: body });
  });
  await login(page, "pedro");
  await openLobby(page);
  await page.getByRole("button", { name: "Informações" }).click();
  const list = page.getByTestId("member-list");
  await expect(list.getByRole("button", { name: /Pedro Henrique/ })).toBeVisible();

  await page.getByPlaceholder("Buscar membro…").fill("mari");
  await expect(list.getByRole("button", { name: /Marina Costa/ })).toBeVisible();
  await expect(list.getByRole("button", { name: /Pedro Henrique/ })).toBeHidden();

  await page.getByPlaceholder("Buscar membro…").fill("ninguem-com-esse-nome");
  await expect(list).toContainText("Nenhum membro encontrado.");
});
