import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Composer } from "./Composer";

vi.mock("../../hooks/useRealtime", () => ({ cableSend: vi.fn() }));

const png = (name = "gato.png", size = 2048) => new File([new Uint8Array(size)], name, { type: "image/png" });

function setup() {
  const props = {
    conversationId: 1,
    replyTo: null,
    editing: null,
    onCancel: vi.fn(),
    onSend: vi.fn(),
    onSaveEdit: vi.fn(),
    onSendImage: vi.fn(),
    onError: vi.fn(),
  };
  render(<Composer {...props} />);
  const box = screen.getByRole("textbox") as HTMLTextAreaElement;
  return { props, box };
}

describe("Composer", () => {
  afterEach(cleanup);

  beforeEach(() => {
    let n = 0;
    URL.createObjectURL = vi.fn(() => `blob:test/${++n}`);
    URL.revokeObjectURL = vi.fn();
    localStorage.clear();
  });

  it("previews an image and sends it with the caption", () => {
    const { props, box } = setup();
    fireEvent.change(screen.getByTestId("image-input"), { target: { files: [png()] } });
    const preview = screen.getByTestId("attachment-preview");
    expect(preview).toHaveTextContent("gato.png");
    expect(preview).toHaveTextContent("2 KB");
    expect(box).toHaveAttribute("placeholder", "Adicione uma legenda…");

    fireEvent.change(box, { target: { value: "olha  " } });
    fireEvent.keyDown(box, { key: "Enter" });
    expect(props.onSendImage).toHaveBeenCalledWith(expect.any(File), "blob:test/1", "olha");
    expect(props.onSend).not.toHaveBeenCalled();
    expect(screen.queryByTestId("attachment-preview")).toBeNull();
    // Ownership of the preview URL moved to the sender.
    expect(URL.revokeObjectURL).not.toHaveBeenCalled();
  });

  it("removes the preview and frees its URL", () => {
    setup();
    fireEvent.change(screen.getByTestId("image-input"), { target: { files: [png()] } });
    fireEvent.click(screen.getByRole("button", { name: "Remover imagem" }));
    expect(screen.queryByTestId("attachment-preview")).toBeNull();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:test/1");
  });

  it("rejects images that are too big or of the wrong type", () => {
    const { props } = setup();
    fireEvent.change(screen.getByTestId("image-input"), { target: { files: [png("x.png", 11 * 1024 * 1024)] } });
    fireEvent.change(screen.getByTestId("image-input"), {
      target: { files: [new File(["x"], "x.svg", { type: "image/svg+xml" })] },
    });
    expect(props.onError).toHaveBeenNthCalledWith(1, "Imagem maior que 10 MB");
    expect(props.onError).toHaveBeenNthCalledWith(2, expect.stringContaining("Formato não suportado"));
    expect(screen.queryByTestId("attachment-preview")).toBeNull();
  });

  it("inserts emoji at the caret and remembers recents", async () => {
    const { box } = setup();
    fireEvent.change(box, { target: { value: "oi tudo" } });
    box.setSelectionRange(2, 2);
    fireEvent.click(screen.getByRole("button", { name: "Emojis" }));
    fireEvent.click(await screen.findByRole("button", { name: "rosto chorando de rir" }));
    expect(box.value).toBe("oi😂 tudo");
    expect(JSON.parse(localStorage.getItem("braxy:emoji-recent")!)).toEqual(["😂"]);
  });

  it("wraps the selection with ctrl+b and ctrl+i", () => {
    const { box } = setup();
    fireEvent.change(box, { target: { value: "muito bom" } });
    box.setSelectionRange(6, 9);
    fireEvent.keyDown(box, { key: "b", ctrlKey: true });
    expect(box.value).toBe("muito **bom**");
    box.setSelectionRange(0, 5);
    fireEvent.keyDown(box, { key: "i", metaKey: true });
    expect(box.value).toBe("*muito* **bom**");
  });
});
