import { faImage, faPaperPlane, faVolumeHigh, faVolumeXmark, faXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import { t } from "../../i18n";
import type { ChatMessage } from "../../lib/types";
import { useUi } from "../../store/ui";
import { cableSend } from "../../hooks/useRealtime";
import styles from "./Chat.module.css";

export interface ComposerHandle {
  insert: (text: string) => void;
  focus: () => void;
}

interface Props {
  conversationId: number;
  replyTo: ChatMessage | null;
  editing: ChatMessage | null;
  disabled?: string | null;
  onCancel: () => void;
  onSend: (body: string) => void;
  onSaveEdit: (m: ChatMessage, body: string) => void;
  onImage: (file: File) => void;
}

export const Composer = forwardRef<ComposerHandle, Props>(function Composer(props, ref) {
  const { conversationId, replyTo, editing, disabled } = props;
  const [text, setText] = useState("");
  const area = useRef<HTMLTextAreaElement>(null);
  const file = useRef<HTMLInputElement>(null);
  const lastTyping = useRef(0);
  const sound = useUi((s) => s.sound);
  const toggleSound = useUi((s) => s.toggleSound);

  useImperativeHandle(ref, () => ({
    insert: (snippet) => {
      setText((cur) => (cur && !cur.endsWith(" ") ? `${cur} ${snippet}` : cur + snippet));
      area.current?.focus();
    },
    focus: () => area.current?.focus(),
  }));

  // Entering edit mode loads the message body; leaving it clears the box.
  useEffect(() => {
    setText(editing ? editing.body : "");
    if (editing) area.current?.focus();
  }, [editing]);

  useEffect(() => {
    if (replyTo) area.current?.focus();
  }, [replyTo]);

  useEffect(() => {
    setText("");
  }, [conversationId]);

  // Auto-grow up to ~6 lines.
  useEffect(() => {
    const el = area.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 150)}px`;
  }, [text]);

  const submit = () => {
    const body = text.trim();
    if (!body) return;
    if (editing) props.onSaveEdit(editing, body);
    else props.onSend(body);
    setText("");
  };

  const onChange = (value: string) => {
    setText(value);
    const now = Date.now();
    if (value && now - lastTyping.current > 2500) {
      lastTyping.current = now;
      cableSend({ action: "typing", conversation_id: conversationId });
    }
  };

  return (
    <div className={styles.composerWrap}>
      {(replyTo || editing) && (
        <div className={styles.replyBar}>
          <span>
            {editing ? t("chat.editing") : t("chat.replyingTo", { name: replyTo!.author?.name ?? "?" })}
            {replyTo && <em> — {replyTo.body || "📷"}</em>}
          </span>
          <button type="button" className="icon-btn" onClick={props.onCancel} aria-label={t("chat.cancel")}>
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>
      )}
      <div className={styles.composer}>
        <textarea
          ref={area}
          className={styles.textarea}
          rows={1}
          value={text}
          placeholder={disabled ?? t("chat.placeholder")}
          disabled={Boolean(disabled)}
          maxLength={2000}
          aria-label={t("chat.placeholder")}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              submit();
            } else if (e.key === "Escape") {
              props.onCancel();
            }
          }}
          onPaste={(e) => {
            const img = [...e.clipboardData.files].find((f) => f.type.startsWith("image/"));
            if (img) {
              e.preventDefault();
              props.onImage(img);
            }
          }}
        />
        <div className={styles.tools}>
          <button type="button" className="icon-btn" onClick={submit} aria-label={t("chat.send")} title={t("chat.send")} disabled={Boolean(disabled)}>
            <FontAwesomeIcon icon={faPaperPlane} />
          </button>
          <button type="button" className="icon-btn" onClick={() => file.current?.click()} aria-label={t("chat.attach")} title={t("chat.attach")} disabled={Boolean(disabled) || Boolean(editing)}>
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
            accept="image/png,image/jpeg,image/gif,image/webp"
            hidden
            data-testid="image-input"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) props.onImage(f);
              e.target.value = "";
            }}
          />
        </div>
      </div>
    </div>
  );
});
