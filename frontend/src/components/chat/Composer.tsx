import {
  faFaceSmile, faImage, faPaperPlane, faVolumeHigh, faVolumeXmark, faXmark,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import { t } from "../../i18n";
import type { ChatMessage } from "../../lib/types";
import { useUi } from "../../store/ui";
import { cableSend } from "../../hooks/useRealtime";
import styles from "./Chat.module.css";
import { EmojiPicker } from "./EmojiPicker";

export const IMAGE_TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp"];
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

export interface ComposerHandle {
  insert: (text: string) => void;
  focus: () => void;
  attach: (file: File) => void;
}

interface Props {
  conversationId: number;
  replyTo: ChatMessage | null;
  editing: ChatMessage | null;
  disabled?: string | null;
  onCancel: () => void;
  onSend: (body: string) => void;
  onSaveEdit: (m: ChatMessage, body: string) => void;
  /** Takes ownership of `preview` (an object URL) and revokes it when done. */
  onSendImage: (file: File, preview: string, caption: string) => void;
  onError: (text: string) => void;
}

interface Attachment {
  file: File;
  url: string;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / 1024 / 1024).toFixed(1).replace(".", ",")} MB`;
}

export const Composer = forwardRef<ComposerHandle, Props>(function Composer(props, ref) {
  const { conversationId, replyTo, editing, disabled } = props;
  const [text, setText] = useState("");
  const [attachment, setAttachment] = useState<Attachment | null>(null);
  const [emojiOpen, setEmojiOpen] = useState(false);
  const area = useRef<HTMLTextAreaElement>(null);
  const file = useRef<HTMLInputElement>(null);
  const lastTyping = useRef(0);
  const caret = useRef<number | null>(null);
  const attachmentRef = useRef<Attachment | null>(null);
  const sound = useUi((s) => s.sound);
  const toggleSound = useUi((s) => s.toggleSound);

  const replaceAttachment = (next: Attachment | null, revoke = true) => {
    if (revoke && attachmentRef.current) URL.revokeObjectURL(attachmentRef.current.url);
    attachmentRef.current = next;
    setAttachment(next);
  };

  const attach = (f: File) => {
    if (disabled || editing) return;
    if (!IMAGE_TYPES.includes(f.type)) return props.onError(t("chat.imageType"));
    if (f.size > MAX_IMAGE_BYTES) return props.onError(t("chat.imageTooBig"));
    replaceAttachment({ file: f, url: URL.createObjectURL(f) });
    area.current?.focus();
  };

  /** Replaces the selection with `snippet` and puts the caret after it. */
  const insertAtCaret = (snippet: string) => {
    const el = area.current;
    const start = el?.selectionStart ?? text.length;
    const end = el?.selectionEnd ?? text.length;
    setText(text.slice(0, start) + snippet + text.slice(end));
    caret.current = start + snippet.length;
  };

  /** Wraps the selection in `marker` (or inserts an empty pair). */
  const wrapSelection = (marker: string) => {
    const el = area.current;
    if (!el) return;
    const { selectionStart: start, selectionEnd: end } = el;
    const inner = text.slice(start, end);
    setText(text.slice(0, start) + marker + inner + marker + text.slice(end));
    caret.current = inner ? start + inner.length + marker.length * 2 : start + marker.length;
  };

  useImperativeHandle(ref, () => ({
    insert: (snippet) => {
      setText((cur) => (cur && !cur.endsWith(" ") ? `${cur} ${snippet}` : cur + snippet));
      area.current?.focus();
    },
    focus: () => area.current?.focus(),
    attach,
  }));

  // Entering edit mode loads the message body; leaving it clears the box.
  useEffect(() => {
    setText(editing ? editing.body : "");
    if (editing) {
      replaceAttachment(null);
      area.current?.focus();
    }
  }, [editing]);

  useEffect(() => {
    if (replyTo) area.current?.focus();
  }, [replyTo]);

  useEffect(() => {
    setText("");
    replaceAttachment(null);
  }, [conversationId]);

  // Never leak the preview's object URL.
  useEffect(() => () => {
    if (attachmentRef.current) URL.revokeObjectURL(attachmentRef.current.url);
  }, []);

  // Auto-grow up to ~6 lines, and restore the caret after programmatic edits.
  useEffect(() => {
    const el = area.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 150)}px`;
    if (caret.current !== null) {
      el.focus();
      el.setSelectionRange(caret.current, caret.current);
      caret.current = null;
    }
  }, [text]);

  const submit = () => {
    const body = text.trim();
    if (editing) {
      if (body) props.onSaveEdit(editing, body);
      else return;
    } else if (attachment) {
      props.onSendImage(attachment.file, attachment.url, body);
      replaceAttachment(null, false);
    } else if (body) {
      props.onSend(body);
    } else {
      return;
    }
    setText("");
    setEmojiOpen(false);
  };

  const onChange = (value: string) => {
    setText(value);
    const now = Date.now();
    if (value && now - lastTyping.current > 2500) {
      lastTyping.current = now;
      cableSend({ action: "typing", conversation_id: conversationId });
    }
  };

  const busy = Boolean(disabled);

  return (
    <div className={styles.composerWrap}>
      {(replyTo || editing) && (
        <div className={styles.replyBar}>
          <span>
            {editing ? t("chat.editing") : t("chat.replyingTo", { name: replyTo!.author?.name ?? "?" })}
            {replyTo && <em> — {replyTo.body || t("chat.image")}</em>}
          </span>
          <button type="button" className="icon-btn" onClick={props.onCancel} aria-label={t("chat.cancel")}>
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>
      )}
      {attachment && (
        <div className={styles.attachment} data-testid="attachment-preview">
          <img src={attachment.url} alt="" />
          <div className={styles.attachmentInfo}>
            <span className={styles.attachmentName}>{attachment.file.name || t("chat.image")}</span>
            <span className="muted">{formatBytes(attachment.file.size)}</span>
          </div>
          <button
            type="button"
            className="icon-btn"
            onClick={() => {
              replaceAttachment(null);
              area.current?.focus();
            }}
            aria-label={t("chat.removeImage")}
            title={t("chat.removeImage")}
          >
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>
      )}
      <div className={styles.composer}>
        {emojiOpen && (
          <EmojiPicker onPick={insertAtCaret} onClose={() => setEmojiOpen(false)} />
        )}
        <textarea
          ref={area}
          className={styles.textarea}
          rows={1}
          value={text}
          placeholder={disabled ?? (attachment ? t("chat.caption") : t("chat.placeholder"))}
          disabled={busy}
          maxLength={2000}
          aria-label={t("chat.placeholder")}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            const mod = e.ctrlKey || e.metaKey;
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              submit();
            } else if (e.key === "Escape") {
              if (attachment && !replyTo) replaceAttachment(null);
              else props.onCancel();
            } else if (mod && !e.shiftKey && !e.altKey && (e.key === "b" || e.key === "i")) {
              e.preventDefault();
              wrapSelection(e.key === "b" ? "**" : "*");
            }
          }}
          onPaste={(e) => {
            const img = [...e.clipboardData.files].find((f) => f.type.startsWith("image/"));
            if (img) {
              e.preventDefault();
              attach(img);
            }
          }}
        />
        <div className={styles.tools}>
          <button type="button" className="icon-btn" onClick={submit} aria-label={t("chat.send")} title={t("chat.send")} disabled={busy}>
            <FontAwesomeIcon icon={faPaperPlane} />
          </button>
          <button
            type="button"
            className={`icon-btn ${emojiOpen ? styles.toolOn : ""}`}
            onClick={() => setEmojiOpen((o) => !o)}
            aria-label={t("chat.emoji")}
            title={t("chat.emoji")}
            aria-expanded={emojiOpen}
            disabled={busy}
            data-emoji-toggle
          >
            <FontAwesomeIcon icon={faFaceSmile} />
          </button>
          <button type="button" className="icon-btn" onClick={() => file.current?.click()} aria-label={t("chat.attach")} title={t("chat.attach")} disabled={busy || Boolean(editing)}>
            <FontAwesomeIcon icon={faImage} />
          </button>
          <button
            type="button"
            className={`icon-btn ${sound ? "" : styles.muted}`}
            onClick={toggleSound}
            aria-label={sound ? t("chat.soundOn") : t("chat.soundOff")}
            title={sound ? t("chat.soundOn") : t("chat.soundOff")}
            aria-pressed={sound}
          >
            <FontAwesomeIcon icon={sound ? faVolumeHigh : faVolumeXmark} />
          </button>
          <input
            ref={file}
            type="file"
            accept={IMAGE_TYPES.join(",")}
            hidden
            data-testid="image-input"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) attach(f);
              e.target.value = "";
            }}
          />
        </div>
      </div>
    </div>
  );
});
