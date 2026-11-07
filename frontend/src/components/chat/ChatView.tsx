import { useQueryClient } from "@tanstack/react-query";
import { type DragEvent, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { activeConversation } from "../../hooks/useRealtime";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import {
  clearUnread, flattenMessages, patchMessage, removeMessage, trimMessages, upsertMessage, useConversation, useMe,
  useMessages, useSidebar,
} from "../../lib/queries";
import { queueRead } from "../../lib/readQueue";
import type { ChatMessage } from "../../lib/types";
import { useUi } from "../../store/ui";
import { ChatHeader } from "./ChatHeader";
import styles from "./Chat.module.css";
import { Composer, type ComposerHandle } from "./Composer";
import { MessageBubble } from "./MessageBubble";

let tempSeq = 0;

/** History kept in memory (and the DOM) while reading the newest messages. */
const KEEP_MESSAGES = 150;
const TRIM_AT = 300;
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
  /** Images of optimistic messages, by client id, so a retry skips re-uploading. */
  const uploads = useRef(new Map<string, { file: File; preview: string; key?: string }>());
  const [dragging, setDragging] = useState(false);
  const dragDepth = useRef(0);

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
      queueRead(id, newestId);
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

  // Busy rooms keep appending over the socket: at the bottom, drop the old
  // history so the list stays small. Scrolling up pages it back in.
  useEffect(() => {
    if (messages.length > TRIM_AT && stick.current && !isFetchingNextPage) trimMessages(qc, id, KEEP_MESSAGES);
  }, [messages.length, isFetchingNextPage, qc, id]);

  // The list shrinks when the composer grows (preview, reply bar, long
  // drafts): stay pinned to the bottom if we were there.
  useEffect(() => {
    const el = scroller.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(() => {
      if (stick.current) el.scrollTop = el.scrollHeight;
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [convo]);

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
    async (draft: ChatMessage, payload: { body?: string; image_key?: string; reply_to_id?: number }): Promise<boolean> => {
      try {
        const { message } = await api.sendMessage(id, { ...payload, client_id: draft.client_id! });
        upsertMessage(qc, message);
        return true;
      } catch (err) {
        patchMessage(qc, id, draft.id, { pending: false, failed: true });
        fail(err);
        return false;
      }
    },
    [id, qc],
  );

  /** Uploads (once) and posts an optimistic image message. */
  const deliverImage = async (draft: ChatMessage, payload: { body?: string; reply_to_id?: number }) => {
    const entry = uploads.current.get(draft.client_id!);
    if (!entry) return;
    try {
      entry.key ??= (await api.uploadImage(entry.file)).key;
    } catch (err) {
      patchMessage(qc, id, draft.id, { pending: false, failed: true });
      fail(err);
      return;
    }
    if (await deliver(draft, { ...payload, image_key: entry.key })) {
      uploads.current.delete(draft.client_id!);
      // The server copy has replaced the preview by now; give it time to paint.
      window.setTimeout(() => URL.revokeObjectURL(entry.preview), 30_000);
    }
  };

  const send = (body: string, imageUrl: string | null = null) => {
    const draft: ChatMessage = {
      id: -++tempSeq,
      conversation_id: id,
      author: { id: me.id, name: me.name, username: me.username, role: me.role, level: me.level, avatar_url: me.avatar_url },
      body,
      image_url: imageUrl,
      reply_to: replyTo
        ? { id: replyTo.id, author_name: replyTo.author?.name ?? "?", author_role: replyTo.author?.role ?? "member", preview: replyTo.body.slice(0, 80) || t("chat.image") }
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
    setReplyTo(null);
    return draft;
  };

  const sendText = (body: string) => {
    const draft = send(body);
    void deliver(draft, { body, reply_to_id: draft.reply_to?.id });
  };

  const sendImage = (file: File, preview: string, caption: string) => {
    const draft = send(caption, preview);
    uploads.current.set(draft.client_id!, { file, preview });
    void deliverImage(draft, { body: caption || undefined, reply_to_id: draft.reply_to?.id });
  };

  const onRetry = (m: ChatMessage) => {
    patchMessage(qc, id, m.id, { pending: true, failed: false });
    if (m.client_id && uploads.current.has(m.client_id)) {
      void deliverImage(m, { body: m.body || undefined, reply_to_id: m.reply_to?.id });
      return;
    }
    const key = m.image_url?.split("/").pop();
    void deliver(m, { body: m.body || undefined, image_key: key, reply_to_id: m.reply_to?.id });
  };

  const onDelete = async (m: ChatMessage) => {
    if (m.failed) {
      const entry = m.client_id ? uploads.current.get(m.client_id) : undefined;
      if (entry) {
        URL.revokeObjectURL(entry.preview);
        uploads.current.delete(m.client_id!);
      }
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

  const hasFiles = (e: DragEvent) => !disabled && e.dataTransfer.types.includes("Files");

  return (
    <section
      className={styles.chat}
      onDragEnter={(e) => {
        if (!hasFiles(e)) return;
        e.preventDefault();
        dragDepth.current += 1;
        setDragging(true);
      }}
      onDragOver={(e) => {
        if (hasFiles(e)) e.preventDefault();
      }}
      onDragLeave={(e) => {
        if (!hasFiles(e)) return;
        dragDepth.current = Math.max(0, dragDepth.current - 1);
        if (dragDepth.current === 0) setDragging(false);
      }}
      onDrop={(e) => {
        if (!hasFiles(e)) return;
        e.preventDefault();
        dragDepth.current = 0;
        setDragging(false);
        const files = [...e.dataTransfer.files];
        const pick = files.find((f) => f.type.startsWith("image/")) ?? files[0];
        if (pick) composer.current?.attach(pick);
      }}
    >
      {dragging && <div className={styles.dropOverlay}>{t("chat.dropImage")}</div>}
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
        onSend={sendText}
        onSaveEdit={onSaveEdit}
        onSendImage={sendImage}
        onError={(text) => pushToast({ text })}
      />
    </section>
  );
}
