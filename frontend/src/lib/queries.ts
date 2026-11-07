import { type InfiniteData, QueryClient, useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import { api, isUnavailable } from "./api";
import type { ChatMessage, Me, MembersPage, MessagesPage, NotificationsData, SidebarData, Stats } from "./types";

export const keys = {
  session: ["session"] as const,
  sidebar: ["sidebar"] as const,
  conversation: (id: number) => ["conversation", id] as const,
  messages: (id: number) => ["messages", id] as const,
  members: (id: number, q = "") => ["members", id, q] as const,
  notifications: ["notifications"] as const,
  friendships: ["friendships"] as const,
  blocks: ["blocks"] as const,
  sanctions: (id: number) => ["sanctions", id] as const,
  stats: ["stats"] as const,
  profile: (username: string) => ["profile", username] as const,
  search: (q: string) => ["search", q] as const,
};

export const BOOT_RETRY_MS = 3000;

export function useSession() {
  return useQuery({
    queryKey: keys.session,
    queryFn: api.session,
    staleTime: Infinity,
    // A backend that is starting shows the waiting screen right away and is
    // polled until it answers.
    retry: (count, err) => !isUnavailable(err) && count < 1,
    refetchInterval: (query) => (isUnavailable(query.state.error) ? BOOT_RETRY_MS : false),
  });
}

let lastMe: Me | null = null;

/** The signed-in user. Inside the shell it is always set; during the
 *  logout transition it keeps returning the last known user. */
export function useMe(): Me {
  const { data } = useSession();
  if (data?.user) lastMe = data.user;
  if (!lastMe) throw new Error("useMe outside of an authenticated tree");
  return lastMe;
}

export function useSidebar() {
  return useQuery({ queryKey: keys.sidebar, queryFn: api.sidebar });
}

export function useConversation(id: number) {
  return useQuery({ queryKey: keys.conversation(id), queryFn: () => api.conversation(id).then((r) => r.conversation) });
}

export function useMessages(id: number) {
  return useInfiniteQuery({
    queryKey: keys.messages(id),
    queryFn: ({ pageParam }) => api.messages(id, pageParam ? { before: pageParam } : {}),
    initialPageParam: 0,
    getNextPageParam: (last: MessagesPage) => (last.has_more && last.messages.length ? last.messages[0].id : undefined),
    staleTime: Infinity,
  });
}

/** Member pages of a conversation, in join order, filtered by `q`. */
export function useMembers(id: number, q: string) {
  return useInfiniteQuery({
    queryKey: keys.members(id, q),
    queryFn: ({ pageParam }) => api.members(id, { q, cursor: pageParam || undefined }),
    initialPageParam: 0,
    getNextPageParam: (last: MembersPage) => last.next_cursor ?? undefined,
    placeholderData: (prev) => prev,
  });
}

export function useNotifications() {
  return useQuery({ queryKey: keys.notifications, queryFn: api.notifications });
}

export function useStats() {
  return useQuery({ queryKey: keys.stats, queryFn: () => api.stats().then((r) => r.stats) });
}

/** Ids of the users I blocked (their messages show collapsed). */
export function useBlockedIds(): Set<number> {
  const { data } = useQuery({ queryKey: keys.blocks, queryFn: api.blocks, staleTime: 60_000 });
  return useMemo(() => new Set((data?.users ?? []).map((u) => u.id)), [data]);
}

export function useSanctions(id: number, enabled: boolean) {
  return useQuery({ queryKey: keys.sanctions(id), queryFn: () => api.sanctions(id).then((r) => r.sanctions), enabled });
}

export function useFriendships() {
  return useQuery({ queryKey: keys.friendships, queryFn: api.friendships });
}

// -- cache mutators (realtime + optimistic updates) ---------------------

type MessagesCache = InfiniteData<MessagesPage, unknown>;

/** pages[0] is the newest page; messages inside a page are oldest-first. */
export function flattenMessages(data: MessagesCache | undefined): ChatMessage[] {
  if (!data) return [];
  return [...data.pages].reverse().flatMap((p) => p.messages);
}

export function upsertMessage(qc: QueryClient, msg: ChatMessage): void {
  qc.setQueryData<MessagesCache>(keys.messages(msg.conversation_id), (data) => {
    if (!data) return data;
    let found = false;
    const pages = data.pages.map((page) => {
      const messages = page.messages.map((m) => {
        if (m.id === msg.id || (msg.client_id && m.client_id === msg.client_id)) {
          found = true;
          return { ...msg, pending: false, failed: false };
        }
        return m;
      });
      return { ...page, messages };
    });
    if (!found) {
      const first = pages[0] ?? { messages: [], has_more: false };
      const messages = [...first.messages, msg].sort((a, b) => sortKey(a) - sortKey(b));
      pages[0] = { ...first, messages };
    }
    return { ...data, pages };
  });
}

/** Pending messages sort last (they have temporary negative ids). */
function sortKey(m: ChatMessage): number {
  return m.id > 0 ? m.id : Number.MAX_SAFE_INTEGER + m.id;
}

export function patchMessage(qc: QueryClient, conversationId: number, id: number, patch: Partial<ChatMessage>): void {
  qc.setQueryData<MessagesCache>(keys.messages(conversationId), (data) =>
    data && {
      ...data,
      pages: data.pages.map((p) => ({ ...p, messages: p.messages.map((m) => (m.id === id ? { ...m, ...patch } : m)) })),
    },
  );
}

export function removeMessage(qc: QueryClient, conversationId: number, id: number): void {
  qc.setQueryData<MessagesCache>(keys.messages(conversationId), (data) =>
    data && { ...data, pages: data.pages.map((p) => ({ ...p, messages: p.messages.filter((m) => m.id !== id) })) },
  );
}

/**
 * Drops all but the newest `keep` messages of a conversation from the cache.
 * The cut page is marked `has_more`, so scrolling up pages them back in.
 * Returns whether anything was dropped.
 */
export function trimMessages(qc: QueryClient, conversationId: number, keep: number): boolean {
  let trimmed = false;
  qc.setQueryData<MessagesCache>(keys.messages(conversationId), (data) => {
    if (!data) return data;
    const pages: MessagesPage[] = [];
    let count = 0;
    for (const page of data.pages) {
      const room = keep - count;
      if (room <= 0) break;
      if (page.messages.length > room) {
        pages.push({ ...page, messages: page.messages.slice(-room), has_more: true });
        count = keep;
      } else {
        pages.push(page);
        count += page.messages.length;
      }
    }
    const dropped = pages.length < data.pages.length || pages[pages.length - 1] !== data.pages[pages.length - 1];
    if (!dropped) return data;
    trimmed = true;
    const last = pages.length - 1;
    pages[last] = { ...pages[last], has_more: true };
    return { pages, pageParams: data.pageParams.slice(0, pages.length) };
  });
  return trimmed;
}

export function lastMessageId(qc: QueryClient, conversationId: number): number {
  const all = flattenMessages(qc.getQueryData<MessagesCache>(keys.messages(conversationId)));
  for (let i = all.length - 1; i >= 0; i--) if (all[i].id > 0) return all[i].id;
  return 0;
}

export function bumpSidebar(qc: QueryClient, msg: ChatMessage, meId: number, activeId: number | null): boolean {
  let known = false;
  qc.setQueryData<SidebarData>(keys.sidebar, (data) => {
    if (!data) return data;
    const preview = {
      id: msg.id,
      preview: msg.deleted ? "mensagem apagada" : msg.body || (msg.image_url ? "📷 Imagem" : ""),
      author_name: msg.author?.id === meId ? "Você" : msg.author?.name ?? "?",
      created_at: msg.created_at,
    };
    const unreadBump = msg.author?.id !== meId && msg.conversation_id !== activeId ? 1 : 0;
    const groups = data.groups.map((g) => {
      if (g.conversation_id !== msg.conversation_id) return g;
      known = true;
      return { ...g, last_message: preview, activity_at: msg.created_at, unread: g.unread + unreadBump };
    });
    const friends = data.friends.map((f) => {
      if (f.conversation_id !== msg.conversation_id) return f;
      known = true;
      return { ...f, last_message: preview, activity_at: msg.created_at, unread: f.unread + unreadBump };
    });
    const byActivity = <T extends { activity_at: string | null }>(a: T, b: T) =>
      (b.activity_at ? Date.parse(b.activity_at) : 0) - (a.activity_at ? Date.parse(a.activity_at) : 0);
    groups.sort((a, b) => (a.kind === "lobby" ? -1 : b.kind === "lobby" ? 1 : byActivity(a, b)));
    friends.sort(byActivity);
    return { groups, friends };
  });
  return known;
}

export function clearUnread(qc: QueryClient, conversationId: number): void {
  qc.setQueryData<SidebarData>(keys.sidebar, (data) =>
    data && {
      groups: data.groups.map((g) => (g.conversation_id === conversationId ? { ...g, unread: 0 } : g)),
      friends: data.friends.map((f) => (f.conversation_id === conversationId ? { ...f, unread: 0 } : f)),
    },
  );
}

export function setStats(qc: QueryClient, stats: Stats): void {
  qc.setQueryData(keys.stats, stats);
}

export function prependNotification(qc: QueryClient, n: NotificationsData["notifications"][number], unread: number): void {
  qc.setQueryData<NotificationsData>(keys.notifications, (data) => ({
    notifications: [n, ...(data?.notifications ?? []).filter((x) => x.id !== n.id)].slice(0, 40),
    unread_count: unread,
  }));
}
