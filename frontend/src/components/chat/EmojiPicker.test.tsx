import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { EmojiPicker, emojiLabel, searchEmoji } from "./EmojiPicker";

describe("searchEmoji", () => {
  it("matches Portuguese names by word prefix, ignoring accents and case", () => {
    expect(searchEmoji("rir")).toContain("😂");
    expect(searchEmoji("CORACAO")[0]).toBe("❤️");
    expect(searchEmoji("bras")).toEqual(["🇧🇷"]);
    expect(searchEmoji("oculos escuros")).toContain("😎");
    expect(searchEmoji("zzzz")).toEqual([]);
    expect(searchEmoji("   ")).toEqual([]);
  });

  it("labels emoji with their name", () => {
    expect(emojiLabel("🍕")).toBe("pizza");
  });
});

describe("EmojiPicker", () => {
  afterEach(cleanup);

  it("searches, picks the first hit with Enter and walks the grid with arrows", () => {
    localStorage.clear();
    const onPick = vi.fn();
    render(<EmojiPicker onPick={onPick} onClose={vi.fn()} />);
    const search = screen.getByRole("searchbox");
    fireEvent.change(search, { target: { value: "pizza" } });
    expect(screen.getByText("Resultados (1)")).toBeInTheDocument();
    fireEvent.keyDown(search, { key: "Enter" });
    expect(onPick).toHaveBeenCalledWith("🍕");

    cleanup();
    localStorage.clear();
    render(<EmojiPicker onPick={onPick} onClose={vi.fn()} />);
    fireEvent.keyDown(screen.getByRole("searchbox"), { key: "ArrowDown" });
    const first = document.activeElement as HTMLElement;
    expect(first).toHaveAccessibleName("rosto risonho");
    fireEvent.keyDown(first, { key: "ArrowRight" });
    expect(document.activeElement).toHaveAccessibleName("rosto risonho com olhos bem abertos");
    fireEvent.keyDown(document.activeElement!, { key: "ArrowDown" });
    expect(document.activeElement).toBe(screen.getAllByRole("button").filter((b) => b.closest("[role=group]"))[9]);
  });
});
