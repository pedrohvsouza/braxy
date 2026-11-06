import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { RichText } from "./RichText";

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
});
