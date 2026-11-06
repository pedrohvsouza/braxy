import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { activeConversation } from "../../hooks/useRealtime";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import {
  clearUnread, flattenMessages, patchMessage, removeMessage, upsertMessage, useConversation, useMe,
  useMessages, useSidebar,
} from "../../lib/queries";
import type { ChatMessage } from "../../lib/types";
import { useUi } from "../../store/ui";
import { ChatHeader } from "./ChatHeader";
import styles from "./Chat.module.css";
import { Composer, type ComposerHandle } from "./Composer";
import { MessageBubble } from "./MessageBubble";

let tempSeq = 0;
const clientId = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export function ChatView() {
  const id = Number(useParams().id);
  return <Conversation key={id} id={id} />;
}

function Conversation({ id }: { id: number }) {
  const me = useMe();
  const qc = useQueryClient();
  const { data: convo, error } = useConversation(id);
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage, isLoading } = useMessages(id);
  const { data: sidebar } = useSidebar();
  const messages = useMemo(() => flattenMessages(data), [data]);
  const pushToast = useUi((s) => s.pushToast);
  const setRead = useUi((s) => s.setRead);
  const reads = useUi((s) => s.reads[id]);
  const typing = useUi((s) => s.typing[id]);

  const [replyTo, setReplyTo] = useState<ChatMessage | null>(null);
  const [editing, setEditing] = useState<ChatMessage | null>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const composer = useRef<ComposerHandle>(null);
  const stick = useRef(true);
  const prevHeight = useRef<number | null>(null);

  // Active conversation bookkeeping (used by the realtime handler).
  useEffect(() => {
    activeConversation.id = id;
    clearUnread(qc, id);
    return () => {
      if (activeConversation.id === id) activeConversation.id = null;
    };
  }, [id, qc]);

  // Seed DM read cursors from the member list.
  useEffect(() => {
    convo?.members.forEach((m) => setRead(id, m.user.id, m.last_read_message_id));
  }, [convo, id, setRead]);

  // Mark as read whenever the newest real message changes (and the tab is visible).
  const newestId = useMemo(() => {
    for (let i = messages.length - 1; i >= 0; i--) if (messages[i].id > 0) return messages[i].id;
    return 0;
  }, [messages]);
  useEffect(() => {
    if (!newestId) return;
    const mark = () => {
      if (document.hidden) return;
      clearUnread(qc, id);
      void api.markRead(id, newestId).catch(() => undefined);
    };
    mark();
    document.addEventListener("visibilitychange", mark);
    return () => document.removeEventListener("visibilitychange", mark);
  }, [id, newestId, qc]);

  // Scroll: keep the bottom pinned for new messages, keep position when
  // older pages are prepended.
  useLayoutEffect(() => {
    const el = scroller.current;
    if (!el) return;
    if (prevHeight.current !== null) {
      el.scrollTop += el.scrollHeight - prevHeight.current;
      prevHeight.current = null;
    } else if (stick.current) {
      el.scrollTop = el.scrollHeight;
    }
  }, [messages]);

  const onScroll = () => {
    const el = scroller.current;
    if (!el) return;
    stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
    if (el.scrollTop < 80 && hasNextPage && !isFetchingNextPage) {
      prevHeight.current = el.scrollHeight;
      void fetchNextPage();
    }
  };

  const fail = (err: unknown) => pushToast({ text: err instanceof ApiError ? err.errors.join(", ") : t("common.error") });

  const deliver = useCallback(
    async (draft: ChatMessage, payload: { body?: string; image_key?: string; reply_to_id?: number }) => {
      try {
        const { message } = await api.sendMessage(id, { ...payload, client_id: draft.client_id! });
        upsertMessage(qc, message);
      } catch (err) {
        patchMessage(qc, id, draft.id, { pending: false, failed: true });
        fail(err);
      }
    },
    [id, qc],
  );

  const send = (body: string, imageUrl: string | null = null, imageKey?: string) => {
    const draft: ChatMessage = {
      id: -++tempSeq,
      conversation_id: id,
      author: { id: me.id, name: me.name, username: me.username, role: me.role, level: me.level, avatar_url: me.avatar_url },
      body,
      image_url: imageUrl,
      reply_to: replyTo
        ? { id: replyTo.id, author_name: replyTo.author?.name ?? "?", author_role: replyTo.author?.role ?? "member", preview: replyTo.body.slice(0, 80) || "📷 Imagem" }
        : null,
      reactions: [],
      edited: false,
      deleted: false,
      client_id: clientId(),
      created_at: new Date().toISOString(),
      pending: true,
    };
    stick.current = true;
    upsertMessage(qc, draft);
    const payload = { body: body || undefined, image_key: imageKey, reply_to_id: replyTo?.id };
    setReplyTo(null);
    void deliver(draft, payload);
  };

  const onImage = async (file: File) => {
    if (file.size > 10 * 1024 * 1024) {
      pushToast({ text: "Imagem maior que 10 MB" });
      return;
    }
    pushToast({ text: t("chat.uploading") });
    try {
      const { key, url } = await api.uploadImage(file);
      send("", url, key);
    } catch (err) {
      fail(err);
    }
  };

  const onRetry = (m: ChatMessage) => {
    patchMessage(qc, id, m.id, { pending: true, failed: false });
    const key = m.image_url?.split("/").pop();
    void deliver(m, { body: m.body || undefined, image_key: key, reply_to_id: m.reply_to?.id });
  };

  const onDelete = async (m: ChatMessage) => {
    if (m.failed) {
      removeMessage(qc, id, m.id);
      return;
    }
    if (!window.confirm(t("chat.deleteConfirm"))) return;
    try {
      const { message } = await api.deleteMessage(m.id);
      upsertMessage(qc, message);
    } catch (err) {
      fail(err);
    }
  };

  const onReact = (m: ChatMessage, emoji: string) => void api.react(m.id, emoji).catch(fail);

  const onSaveEdit = async (m: ChatMessage, body: string) => {
    setEditing(null);
    if (body === m.body) return;
    try {
      const { message } = await api.editMessage(m.id, body);
      upsertMessage(qc, message);
    } catch (err) {
      fail(err);
    }
  };

  const onJump = (target: number) => {
    const el = document.getElementById(`msg-${target}`);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.classList.add(styles.flash);
      window.setTimeout(() => el.classList.remove(styles.flash), 1200);
    }
  };

  if (error) {
    return <div className={styles.center}>{error instanceof ApiError ? error.errors[0] : t("common.error")}</div>;
  }
  if (!convo) return <div className={styles.center}>{t("common.loading")}</div>;

  const other = convo.kind === "dm" ? convo.members.find((m) => m.user.id !== me.id) : undefined;
  const friend = other ? sidebar?.friends.find((f) => f.user.id === other.user.id) : undefined;
  const otherOnline = friend?.online ?? other?.online ?? false;
  const disabled = convo.kind === "dm" && sidebar && !friend ? t("chat.notFriends") : null;

  // DM "Visto": my newest message the other side has read.
  let seenId = 0;
  if (other) {
    const cursor = reads?.[other.user.id] ?? 0;
    for (let i = messages.length - 1; i >= 0; i--) {
      const m = messages[i];
      if (m.author?.id === me.id && m.id > 0) {
        if (m.id <= cursor) seenId = m.id;
        break;
      }
    }
  }

  const typers = Object.values(typing ?? {}).map((x) => x.name);

  return (
    <section className={styles.chat}>
      <ChatHeader convo={convo} me={me} online={otherOnline} />
      <div className={styles.scroller} ref={scroller} onScroll={onScroll} data-testid="message-list">
        {isLoading && <p className={styles.notice}>{t("common.loading")}</p>}
        {isFetchingNextPage && <p className={styles.notice}>{t("chat.loadingOlder")}</p>}
        {!isLoading && !hasNextPage && <p className={styles.notice}>{t("chat.beginning")}</p>}
        {messages.map((m) => (
          <MessageBubble
            key={m.client_id ?? m.id}
            message={m}
            me={me}
            canModerate={convo.can_moderate}
            seen={m.id === seenId}
            onReply={(msg) => {
              setEditing(null);
              setReplyTo(msg);
            }}
            onMention={(username) => composer.current?.insert(`@${username} `)}
            onEdit={(msg) => {
              setReplyTo(null);
              setEditing(msg);
            }}
            onDelete={onDelete}
            onReact={onReact}
            onRetry={onRetry}
            onJump={onJump}
          />
        ))}
      </div>
      <div className={styles.typingLine} aria-live="polite">
        {typers.length === 1 && t("chat.typingOne", { name: typers[0] })}
        {typers.length > 1 && t("chat.typingMany", { names: typers.join(", ") })}
      </div>
      <Composer
        ref={composer}
        conversationId={id}
        replyTo={replyTo}
        editing={editing}
        disabled={disabled}
        onCancel={() => {
          setReplyTo(null);
          setEditing(null);
        }}
        onSend={(body) => send(body)}
        onSaveEdit={onSaveEdit}
        onImage={onImage}
      />
    </section>
  );
}
