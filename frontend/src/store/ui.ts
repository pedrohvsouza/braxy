import { create } from "zustand";
import type { AppNotification } from "../lib/types";

export interface Toast {
  id: number;
  text: string;
  notification?: AppNotification;
}

type Modal =
  | { kind: "profile"; username: string }
  | { kind: "settings" }
  | { kind: "createGroup" }
  | { kind: "groupInfo"; conversationId: number }
  | { kind: "requests" }
  | null;

function loadSound(): boolean {
  try {
    return localStorage.getItem("braxy:sound") !== "off";
  } catch {
    return true;
  }
}

function loadDesktopNotify(): boolean {
  try {
    return localStorage.getItem("braxy:desktop-notify") === "on";
  } catch {
    return false;
  }
}

interface UiState {
  connected: boolean;
  everConnected: boolean;
  latency: number | null;
  sound: boolean;
  /** Native browser notifications while the app is in the background (opt-in). */
  desktopNotify: boolean;
  sidebarOpen: boolean;
  modal: Modal;
  toasts: Toast[];
  /** conversation id -> user id -> {name, until} */
  typing: Record<number, Record<number, { name: string; until: number }>>;
  /** DM read cursors: conversation id -> user id -> last read message id */
  reads: Record<number, Record<number, number>>;
  searchFocus: number;

  setConnected: (connected: boolean) => void;
  setLatency: (ms: number) => void;
  toggleSound: () => void;
  setDesktopNotify: (on: boolean) => void;
  setSidebarOpen: (open: boolean) => void;
  openModal: (modal: Modal) => void;
  closeModal: () => void;
  pushToast: (toast: Omit<Toast, "id">) => void;
  dismissToast: (id: number) => void;
  setTyping: (conversationId: number, userId: number, name: string) => void;
  pruneTyping: () => void;
  setRead: (conversationId: number, userId: number, messageId: number) => void;
  focusSearch: () => void;
}

let toastSeq = 0;

export const useUi = create<UiState>((set) => ({
  connected: false,
  everConnected: false,
  latency: null,
  sound: loadSound(),
  desktopNotify: loadDesktopNotify(),
  sidebarOpen: false,
  modal: null,
  toasts: [],
  typing: {},
  reads: {},
  searchFocus: 0,

  setConnected: (connected) => set((s) => ({ connected, everConnected: s.everConnected || connected })),
  setLatency: (latency) => set({ latency }),
  toggleSound: () =>
    set((s) => {
      try {
        localStorage.setItem("braxy:sound", s.sound ? "off" : "on");
      } catch {
        /* private mode */
      }
      return { sound: !s.sound };
    }),
  setDesktopNotify: (desktopNotify) => {
    try {
      localStorage.setItem("braxy:desktop-notify", desktopNotify ? "on" : "off");
    } catch {
      /* private mode */
    }
    set({ desktopNotify });
  },
  setSidebarOpen: (sidebarOpen) => set({ sidebarOpen }),
  openModal: (modal) => set({ modal, sidebarOpen: false }),
  closeModal: () => set({ modal: null }),
  pushToast: (toast) => set((s) => ({ toasts: [...s.toasts.slice(-3), { ...toast, id: ++toastSeq }] })),
  dismissToast: (id) => set((s) => ({ toasts: s.toasts.filter((x) => x.id !== id) })),
  setTyping: (conversationId, userId, name) =>
    set((s) => ({
      typing: {
        ...s.typing,
        [conversationId]: { ...(s.typing[conversationId] ?? {}), [userId]: { name, until: Date.now() + 4000 } },
      },
    })),
  pruneTyping: () =>
    set((s) => {
      const now = Date.now();
      let changed = false;
      const next: UiState["typing"] = {};
      for (const [cid, users] of Object.entries(s.typing)) {
        const kept = Object.fromEntries(Object.entries(users).filter(([, v]) => v.until > now));
        if (Object.keys(kept).length !== Object.keys(users).length) changed = true;
        if (Object.keys(kept).length) next[Number(cid)] = kept;
      }
      return changed ? { typing: next } : s;
    }),
  setRead: (conversationId, userId, messageId) =>
    set((s) => ({
      reads: {
        ...s.reads,
        [conversationId]: {
          ...(s.reads[conversationId] ?? {}),
          [userId]: Math.max(messageId, s.reads[conversationId]?.[userId] ?? 0),
        },
      },
    })),
  focusSearch: () => set((s) => ({ searchFocus: s.searchFocus + 1, sidebarOpen: true })),
}));
