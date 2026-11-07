import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";
import { bumpSidebar, flattenMessages, keys, trimMessages, upsertMessage } from "./queries";
import type { ChatMessage, SidebarData } from "./types";

const author = { id: 1, name: "Ana", username: "ana", role: "member" as const, level: 1, avatar_url: null };

function msg(id: number, extra: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id, conversation_id: 7, author, body: `m${id}`, image_url: null, reply_to: null, reactions: [],
    edited: false, deleted: false, client_id: null, created_at: new Date(id * 1000).toISOString(), ...extra,
  };
}

function seed(qc: QueryClient, pages: ChatMessage[][]) {
  qc.setQueryData(keys.messages(7), { pages: pages.map((messages) => ({ messages, has_more: false })), pageParams: [0] });
}

describe("message cache", () => {
  it("flattens pages oldest-first (pages[0] is the newest page)", () => {
    const qc = new QueryClient();
    seed(qc, [[msg(3), msg(4)], [msg(1), msg(2)]]);
    expect(flattenMessages(qc.getQueryData(keys.messages(7))).map((m) => m.id)).toEqual([1, 2, 3, 4]);
  });

  it("replaces an optimistic message by client_id instead of duplicating it", () => {
    const qc = new QueryClient();
    seed(qc, [[msg(1)]]);
    upsertMessage(qc, msg(-1, { client_id: "c1", pending: true }));
    upsertMessage(qc, msg(2, { client_id: "c1" }));
    upsertMessage(qc, msg(2, { client_id: "c1" })); // broadcast after the POST response
    const all = flattenMessages(qc.getQueryData(keys.messages(7)));
    expect(all.map((m) => m.id)).toEqual([1, 2]);
    expect(all[1].pending).toBe(false);
  });

  it("trims to the newest messages and lets older pages load again", () => {
    const qc = new QueryClient();
    seed(qc, [[msg(5), msg(6), msg(7)], [msg(3), msg(4)], [msg(1), msg(2)]]);
    qc.setQueryData(keys.messages(7), (d: { pages: unknown[]; pageParams: unknown[] }) => ({ ...d, pageParams: [0, 5, 3] }));
    expect(trimMessages(qc, 7, 4)).toBe(true);
    const data = qc.getQueryData<{ pages: { messages: ChatMessage[]; has_more: boolean }[]; pageParams: unknown[] }>(keys.messages(7))!;
    expect(flattenMessages(data as never).map((m) => m.id)).toEqual([4, 5, 6, 7]);
    expect(data.pages.map((p) => p.has_more)).toEqual([false, true]);
    expect(data.pageParams).toEqual([0, 5]);
    // Nothing left to drop: the cache stays untouched.
    expect(trimMessages(qc, 7, 4)).toBe(false);
    expect(qc.getQueryData(keys.messages(7))).toBe(data);
  });

  it("keeps pending messages after confirmed ones", () => {
    const qc = new QueryClient();
    seed(qc, [[msg(1)]]);
    upsertMessage(qc, msg(-5, { client_id: "x", pending: true }));
    upsertMessage(qc, msg(9));
    expect(flattenMessages(qc.getQueryData(keys.messages(7))).map((m) => m.id)).toEqual([1, 9, -5]);
  });
});

describe("sidebar bump", () => {
  it("updates preview, unread and ordering", () => {
    const qc = new QueryClient();
    const data: SidebarData = {
      groups: [],
      friends: [
        { user: { ...author, id: 2, username: "bob", name: "Bob" }, online: true, conversation_id: 3, unread: 0, last_message: null, activity_at: "2026-01-01T00:00:00Z" },
        { user: author, online: false, conversation_id: 7, unread: 0, last_message: null, activity_at: "2025-01-01T00:00:00Z" },
      ],
    };
    qc.setQueryData(keys.sidebar, data);
    expect(bumpSidebar(qc, msg(50, { created_at: "2026-06-01T00:00:00Z" }), 99, null)).toBe(true);
    const after = qc.getQueryData<SidebarData>(keys.sidebar)!;
    expect(after.friends[0].conversation_id).toBe(7);
    expect(after.friends[0].unread).toBe(1);
    expect(after.friends[0].last_message?.preview).toBe("m50");
    // Unknown conversation -> caller refetches.
    expect(bumpSidebar(qc, msg(51, { conversation_id: 1234 }), 99, null)).toBe(false);
  });
});
