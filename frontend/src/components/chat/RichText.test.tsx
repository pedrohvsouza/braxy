import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { isJumboEmoji, plainText } from "../../lib/markup";
import { RichText } from "./RichText";

const html = (text: string) => render(<div><RichText text={text} me="pedro" /></div>).container;

describe("RichText", () => {
  it("links URLs, highlights mentions and never renders HTML", () => {
    const { container } = render(
      <p>
        <RichText text={"oi @Pedro veja https://braxy.dev/x.\n<b>não</b>"} me="pedro" />
      </p>,
    );
    const link = screen.getByRole("link");
    expect(link).toHaveAttribute("href", "https://braxy.dev/x");
    expect(link).toHaveAttribute("rel", expect.stringContaining("noopener"));
    expect(screen.getByText("@Pedro").className).toMatch(/mentionMe/);
    expect(container.querySelector("b")).toBeNull();
    expect(container.textContent).toContain("<b>não</b>");
    expect(container.querySelectorAll("br")).toHaveLength(1);
  });

  it("renders bold, italics, strike and inline code", () => {
    const c = html("**forte** *leve* _também_ ~~velho~~ `x = 1`");
    expect(c.querySelector("strong")?.textContent).toBe("forte");
    expect([...c.querySelectorAll("em")].map((e) => e.textContent)).toEqual(["leve", "também"]);
    expect(c.querySelector("s")?.textContent).toBe("velho");
    expect(c.querySelector("code")?.textContent).toBe("x = 1");
  });

  it("nests formatting but keeps code literal", () => {
    const c = html("**veja _isso_ @rafa** `**não**`");
    expect(c.querySelector("strong em")?.textContent).toBe("isso");
    expect(c.querySelector("strong span")?.textContent).toBe("@rafa");
    expect(c.querySelector("code")?.textContent).toBe("**não**");
    expect(c.querySelectorAll("strong")).toHaveLength(1);
  });

  it("leaves snake_case, math and URLs with markers alone", () => {
    const c = html("user_name_x 2 * 3 * 4 https://a.dev/a_b_c/*x*");
    expect(c.querySelector("em")).toBeNull();
    expect(c.querySelector("a")).toHaveAttribute("href", "https://a.dev/a_b_c/*x");
  });

  it("renders fenced code blocks without extra breaks", () => {
    const c = html("antes\n```js\nconst a = **1**;\nfoo()\n```\ndepois");
    const pre = c.querySelector("pre code");
    expect(pre?.textContent).toBe("const a = **1**;\nfoo()");
    expect(c.querySelector("strong")).toBeNull();
    expect(c.querySelectorAll("br")).toHaveLength(0);
  });

  it("renders quote lines as blocks", () => {
    const c = html("> citado\nresposta");
    expect(c.querySelector("[class*=mdQuote]")?.textContent).toBe("citado");
    expect(c.querySelectorAll("br")).toHaveLength(0);
    expect(c.textContent).toContain("resposta");
  });

  it("hides spoilers until clicked", () => {
    html("o fim: ||ele morre||");
    const spoiler = screen.getByRole("button", { name: "Revelar spoiler" });
    expect(spoiler.className).not.toMatch(/spoilerShown/);
    fireEvent.click(spoiler);
    expect(screen.getByText("ele morre").className).toMatch(/spoilerShown/);
  });
});

describe("plainText", () => {
  it("strips markers and masks spoilers", () => {
    expect(plainText("**oi** _tudo_ ~~bem~~ `x` ||segredo|| > a")).toBe("oi tudo bem x ▒▒▒ > a");
    expect(plainText("> citação\n```\ncode\n```")).toBe("citação\ncode");
  });
});

describe("isJumboEmoji", () => {
  it("accepts up to three emoji only", () => {
    expect(isJumboEmoji("🔥")).toBe(true);
    expect(isJumboEmoji(" 👍🏽 ❤️ 🇧🇷 ")).toBe(true);
    expect(isJumboEmoji("👨‍👩‍👧")).toBe(true);
    expect(isJumboEmoji("🔥🔥🔥🔥")).toBe(false);
    expect(isJumboEmoji("oi 🔥")).toBe(false);
    expect(isJumboEmoji("123")).toBe(false);
  });
});
