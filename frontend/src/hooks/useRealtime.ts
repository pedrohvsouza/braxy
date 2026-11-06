import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { Cable, type CableEvent } from "../lib/cable";
import { notificationText } from "../lib/notificationText";
import {
  bumpSidebar, keys, lastMessageId, patchMessage, prependNotification, setStats, upsertMessage,
} from "../lib/queries";
import { playPing } from "../lib/sound";
import type { AppNotification, ChatMessage, Me, ReactionSummary, SidebarData, Stats } from "../lib/types";
import { useUi } from "../store/ui";

/** The id of the conversation currently on screen (read by the socket handler). */
export const activeConversation = { id: null as number | null };

let cableRef: Cable | null = null;

export function cableSend(data: Record<string, unknown>): void {
  cableRef?.send(data);
}

/** Connects the ChatChannel and folds every event into the query cache. */
export function useRealtime(me: Me): void {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const meRef = useRef(me);
  meRef.current = me;

  useEffect(() => {
    const ui = useUi.getState;

    const onMessage = (msg: ChatMessage, created: boolean) => {
      upsertMessage(qc, msg);
      if (!created) return;
      const mine = msg.author?.id === meRef.current.id;
      const active = activeConversation.id === msg.conversation_id;
      if (!bumpSidebar(qc, msg, meRef.current.id, activeConversation.id)) {
        void qc.invalidateQueries({ queryKey: keys.sidebar });
      }
      if (!mine && (document.hidden || !active) && ui().sound) playPing();
      if (!mine && active && !document.hidden) void api.markRead(msg.conversation_id, msg.id).catch(() => undefined);
    };

    const handlers: Record<string, (e: CableEvent) => void> = {
      "message.created": (e) => onMessage(e.message as ChatMessage, true),
      "message.updated": (e) => {
        const msg = e.message as ChatMessage;
        onMessage(msg, false);
        void qc.invalidateQueries({ queryKey: keys.sidebar });
      },
      "reaction.updated": (e) => {
        const cid = findConversationOf(Number(e.message_id));
        if (cid) patchMessage(qc, cid, Number(e.message_id), { reactions: e.reactions as ReactionSummary[] });
      },
      typing: (e) => {
        const user = e.user as { id: number; name: string };
        if (user.id !== meRef.current.id) ui().setTyping(Number(e.conversation_id), user.id, user.name);
      },
      read: (e) => ui().setRead(Number(e.conversation_id), Number(e.user_id), Number(e.message_id)),
      "conversation.added": (e) => {
        cableSend({ action: "follow", conversation_id: e.conversation_id });
        void qc.invalidateQueries({ queryKey: keys.sidebar });
      },
      "conversation.removed": (e) => {
        const cid = Number(e.conversation_id);
        cableSend({ action: "unfollow", conversation_id: cid });
        qc.removeQueries({ queryKey: keys.messages(cid) });
        void qc.invalidateQueries({ queryKey: keys.sidebar });
        if (activeConversation.id === cid) navigate("/");
      },
      "conversation.updated": (e) => {
        void qc.invalidateQueries({ queryKey: keys.conversation(Number(e.conversation_id)) });
        void qc.invalidateQueries({ queryKey: keys.sidebar });
      },
      "notification.created": (e) => {
        const n = e.notification as AppNotification;
        prependNotification(qc, n, Number(e.unread_count));
        ui().pushToast({ text: notificationText(n), notification: n });
        if (ui().sound) playPing();
        if (n.kind === "friend_request" || n.kind === "friend_accepted") {
          void qc.invalidateQueries({ queryKey: keys.friendships });
        }
      },
      "friendship.changed": () => {
        void qc.invalidateQueries({ queryKey: keys.sidebar });
        void qc.invalidateQueries({ queryKey: keys.friendships });
        void qc.invalidateQueries({ queryKey: ["search"] });
        void qc.invalidateQueries({ queryKey: ["profile"] });
      },
      presence: (e) => {
        qc.setQueryData<SidebarData>(keys.sidebar, (data) =>
          data && {
            ...data,
            friends: data.friends.map((f) => (f.user.id === Number(e.user_id) ? { ...f, online: Boolean(e.online) } : f)),
          },
        );
      },
      "xp.updated": (e) => {
        qc.setQueryData<{ user: Me | null }>(keys.session, (data) =>
          data?.user
            ? {
                user: {
                  ...data.user,
                  xp: Number(e.xp),
                  level: Number(e.level),
                  level_xp: Number(e.level_xp),
                  level_need: Number(e.level_need),
                },
              }
            : data,
        );
      },
      stats: (e) => setStats(qc, e.stats as Stats),
    };

    // Messages arrive with their conversation id, reactions do not: look the
    // message up in whatever pages are cached.
    const findConversationOf = (messageId: number): number | null => {
      for (const q of qc.getQueryCache().findAll({ queryKey: ["messages"] })) {
        const data = q.state.data as { pages: { messages: ChatMessage[] }[] } | undefined;
        if (data?.pages.some((p) => p.messages.some((m) => m.id === messageId))) return Number(q.queryKey[1]);
      }
      return null;
    };

    const cable = new Cable({
      onEvent: (e) => handlers[e.type]?.(e),
      onLatency: (ms) => ui().setLatency(ms),
      onStatus: (connected, reconnected) => {
        ui().setConnected(connected);
        if (connected && reconnected) {
          // Catch up on whatever happened while offline.
          void qc.invalidateQueries({ queryKey: keys.sidebar });
          void qc.invalidateQueries({ queryKey: keys.notifications });
          const cid = activeConversation.id;
          if (cid) {
            const after = lastMessageId(qc, cid);
            void api.messages(cid, after ? { after } : {}).then((page) => page.messages.forEach((m) => upsertMessage(qc, m)));
          }
        }
      },
    });
    cableRef = cable;
    const prune = window.setInterval(() => ui().pruneTyping(), 1000);
    return () => {
      window.clearInterval(prune);
      cable.close();
      cableRef = null;
    };
  }, [qc, navigate]);
}
