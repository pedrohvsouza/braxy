import { act, cleanup, fireEvent, render, renderHook, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ChatMessage } from "../lib/types";
import { ANNOUNCE_WINDOW_MS, useAnnouncer } from "./chat/useAnnouncer";
import { Modal } from "./common/Modal";

const user = (id: number, name: string) => ({ id, name, username: name.toLowerCase(), role: "member" as const, level: 1, avatar_url: null });

function msg(id: number, authorId: number, body = `m${id}`): ChatMessage {
  return {
    id, conversation_id: 1, author: user(authorId, authorId === 1 ? "Eu" : "Ana"), body, image_url: null, reply_to: null,
    reactions: [], edited: false, deleted: false, client_id: null, created_at: new Date().toISOString(),
  };
}

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("useAnnouncer", () => {
  it("announces others' new messages, grouped, never the history or my own", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(({ list }) => useAnnouncer(list, 1), { initialProps: { list: [msg(1, 2), msg(2, 2)] } });
    act(() => vi.advanceTimersByTime(ANNOUNCE_WINDOW_MS));
    expect(result.current).toBe(""); // history

    rerender({ list: [msg(1, 2), msg(2, 2), msg(3, 2, "**oi** ||segredo||")] });
    rerender({ list: [msg(1, 2), msg(2, 2), msg(3, 2, "**oi** ||segredo||"), msg(4, 1)] });
    act(() => vi.advanceTimersByTime(ANNOUNCE_WINDOW_MS));
    expect(result.current).toBe("Nova mensagem de Ana: oi ▒▒▒");

    rerender({ list: [msg(3, 2), msg(5, 2), msg(6, 2), msg(7, 2)] });
    act(() => vi.advanceTimersByTime(ANNOUNCE_WINDOW_MS));
    expect(result.current).toBe("3 novas mensagens");
  });
});

describe("Modal", () => {
  it("moves focus in, keeps Tab inside and gives focus back on close", () => {
    const opener = document.createElement("button");
    document.body.appendChild(opener);
    opener.focus();
    const { unmount } = render(
      <Modal title="Teste" onClose={vi.fn()}>
        <input aria-label="campo" />
        <button type="button">ok</button>
      </Modal>,
    );
    expect(screen.getByRole("dialog", { name: "Teste" })).toBeInTheDocument();
    expect(document.activeElement).toBe(screen.getByLabelText("campo"));
    screen.getByRole("button", { name: "ok" }).focus();
    fireEvent.keyDown(document, { key: "Tab" });
    expect(document.activeElement).toBe(screen.getByRole("button", { name: "Fechar" }));
    fireEvent.keyDown(document, { key: "Tab", shiftKey: true });
    expect(document.activeElement).toBe(screen.getByRole("button", { name: "ok" }));
    unmount();
    expect(document.activeElement).toBe(opener);
    opener.remove();
  });
});
