// REST client. Same-origin (Vite proxy in dev), so the HttpOnly session
// cookie is automatic; every mutation echoes the `saci_csrf` cookie.
import type {
  ChatMessage, ConversationDetail, FriendRequest, FriendshipState, Me, MessagesPage,
  NotificationsData, Profile, SearchResult, SidebarData, Stats,
} from "./types";

export class ApiError extends Error {
  status: number;
  errors: string[];

  constructor(status: number, errors: string[]) {
    super(errors[0] ?? `HTTP ${status}`);
    this.status = status;
    this.errors = errors;
  }
}

function csrfToken(): string {
  const m = document.cookie.match(/(?:^|;\s*)saci_csrf=([^;]+)/);
  return m ? decodeURIComponent(m[1]) : "";
}

async function request<T>(method: string, path: string, body?: unknown, retried = false): Promise<T> {
  const isForm = body instanceof FormData;
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined && !isForm) headers["Content-Type"] = "application/json";
  if (method !== "GET") headers["X-CSRF-Token"] = csrfToken();

  let res: Response;
  try {
    res = await fetch(path, {
      method,
      headers,
      credentials: "same-origin",
      body: body === undefined ? undefined : isForm ? body : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, ["Sem conexão com o servidor"]);
  }

  const text = await res.text();
  let data: unknown = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = null;
  }

  if (!res.ok) {
    const obj = (data ?? {}) as { error?: string; errors?: string[] };
    // A rotated CSRF cookie is recoverable once: refresh it and retry.
    if (res.status === 403 && obj.error === "token CSRF inválido" && !retried) {
      await fetch("/api/session", { credentials: "same-origin" });
      return request<T>(method, path, body, true);
    }
    const errors = obj.errors ?? (obj.error ? [obj.error] : [`Erro ${res.status}`]);
    throw new ApiError(res.status, errors);
  }
  return data as T;
}

const get = <T>(path: string) => request<T>("GET", path);
const post = <T>(path: string, body: unknown = {}) => request<T>("POST", path, body);
const patch = <T>(path: string, body: unknown) => request<T>("PATCH", path, body);
const del = <T>(path: string) => request<T>("DELETE", path);

function fileForm(file: File): FormData {
  const form = new FormData();
  form.append("file", file);
  return form;
}

export const api = {
  session: () => get<{ user: Me | null }>("/api/session"),
  login: (login: string, password: string) => post<{ user: Me }>("/api/session", { login, password }),
  signup: (data: { name: string; username: string; email: string; password: string }) =>
    post<{ user: Me }>("/api/signup", data),
  logout: () => del<{ ok: boolean }>("/api/session"),

  updateProfile: (data: { name?: string; bio?: string; birthday?: string }) => patch<{ user: Me }>("/api/me", data),
  changePassword: (current_password: string, password: string) =>
    patch<{ ok: boolean }>("/api/me/password", { current_password, password }),
  uploadAvatar: (file: File) => post<{ user: Me }>("/api/me/avatar", fileForm(file)),

  searchUsers: (q: string) => get<{ users: SearchResult[] }>(`/api/users?q=${encodeURIComponent(q)}`),
  profile: (username: string) => get<{ user: Profile }>(`/api/users/${encodeURIComponent(username)}`),

  friendships: () => get<{ incoming: FriendRequest[]; outgoing: FriendRequest[] }>("/api/friendships"),
  requestFriend: (user_id: number) => post<{ friendship: FriendshipState }>("/api/friendships", { user_id }),
  acceptFriend: (id: number) => post<{ friendship: FriendshipState }>(`/api/friendships/${id}/accept`),
  removeFriendship: (id: number) => del<{ friendship: FriendshipState }>(`/api/friendships/${id}`),

  sidebar: () => get<SidebarData>("/api/sidebar"),
  conversation: (id: number) => get<{ conversation: ConversationDetail }>(`/api/conversations/${id}`),
  openDm: (user_id: number) => post<{ conversation: ConversationDetail }>("/api/conversations/dm", { user_id }),
  createGroup: (name: string, member_ids: number[]) =>
    post<{ conversation: ConversationDetail }>("/api/conversations", { name, member_ids }),
  renameGroup: (id: number, name: string) => patch<{ conversation: ConversationDetail }>(`/api/conversations/${id}`, { name }),
  uploadGroupAvatar: (id: number, file: File) =>
    post<{ conversation: ConversationDetail }>(`/api/conversations/${id}/avatar`, fileForm(file)),
  addMembers: (id: number, user_ids: number[]) =>
    post<{ conversation: ConversationDetail }>(`/api/conversations/${id}/members`, { user_ids }),
  removeMember: (id: number, user_id: number) => del<{ ok: boolean }>(`/api/conversations/${id}/members/${user_id}`),
  markRead: (id: number, message_id: number) => post<{ ok: boolean }>(`/api/conversations/${id}/read`, { message_id }),

  messages: (id: number, opts: { before?: number; after?: number } = {}) => {
    const qs = opts.before ? `?before=${opts.before}` : opts.after ? `?after=${opts.after}` : "";
    return get<MessagesPage>(`/api/conversations/${id}/messages${qs}`);
  },
  sendMessage: (id: number, data: { body?: string; image_key?: string; reply_to_id?: number; client_id: string }) =>
    post<{ message: ChatMessage }>(`/api/conversations/${id}/messages`, data),
  editMessage: (id: number, body: string) => patch<{ message: ChatMessage }>(`/api/messages/${id}`, { body }),
  deleteMessage: (id: number) => del<{ message: ChatMessage }>(`/api/messages/${id}`),
  react: (id: number, emoji: string) => post<{ ok: boolean }>(`/api/messages/${id}/reactions`, { emoji }),
  uploadImage: (file: File) => post<{ key: string; url: string }>("/api/uploads", fileForm(file)),

  notifications: () => get<NotificationsData>("/api/notifications"),
  readNotification: (id: number) => post<{ unread_count: number }>(`/api/notifications/${id}/read`),
  readAllNotifications: () => post<{ unread_count: number }>("/api/notifications/read_all"),

  stats: () => get<{ stats: Stats }>("/api/stats"),
};
