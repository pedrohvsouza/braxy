import { faAt, faFaceSmile, faPen, faReply, faTrash } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { memo, useState } from "react";
import { t } from "../../i18n";
import { fullTimestamp } from "../../lib/format";
import type { ChatMessage, Me } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Chat.module.css";
import { RichText } from "./RichText";

export const EMOJIS = ["👍", "❤️", "😂", "😮", "😢", "🔥"];

interface Props {
  message: ChatMessage;
  me: Me;
  canModerate: boolean;
  seen: boolean;
  onReply: (m: ChatMessage) => void;
  onMention: (username: string) => void;
  onEdit: (m: ChatMessage) => void;
  onDelete: (m: ChatMessage) => void;
  onReact: (m: ChatMessage, emoji: string) => void;
  onRetry: (m: ChatMessage) => void;
  onJump: (id: number) => void;
}

export const MessageBubble = memo(function MessageBubble(props: Props) {
  const { message: m, me, canModerate, seen } = props;
  const openModal = useUi((s) => s.openModal);
  const [picker, setPicker] = useState(false);
  const author = m.author;
  const mine = author?.id === me.id;
  const name = author?.name ?? "Usuário removido";
  const showProfile = () => author && openModal({ kind: "profile", username: author.username });

  return (
    <div
      className={`${styles.msg} ${mine ? styles.mine : ""} ${m.pending ? styles.pending : ""}`}
      id={`msg-${m.id}`}
      data-testid="message"
      onMouseLeave={() => setPicker(false)}
    >
      <button className={styles.msgAvatar} type="button" onClick={showProfile} aria-label={name}>
        <Avatar name={name} url={author?.avatar_url} size={44} />
      </button>
      <div className={styles.bubbleCol}>
        <div className={styles.bubble}>
          <div className={styles.msgHead}>
            {author ? (
              <UserName name={author.name} role={author.role} level={author.level} showRole={false} onClick={showProfile} />
            ) : (
              <span className="muted">{name}</span>
            )}
          </div>

          {m.reply_to && !m.deleted && (
            <button type="button" className={styles.quote} onClick={() => props.onJump(m.reply_to!.id)}>
              <span className={`role-name role-${m.reply_to.author_role}`}>{m.reply_to.author_name}</span>
              <span>{m.reply_to.preview}</span>
            </button>
          )}

          {m.deleted ? (
            <p className={`${styles.body} ${styles.deleted}`}>{t("chat.deleted")}</p>
          ) : (
            <>
              {m.body && (
                <p className={styles.body}>
                  <RichText text={m.body} me={me.username} />
                </p>
              )}
              {m.image_url && (
                <a href={m.image_url} target="_blank" rel="noreferrer" className={styles.image}>
                  <img src={m.image_url} alt="" loading="lazy" />
                </a>
              )}
            </>
          )}

          <div className={styles.meta}>
            <time dateTime={m.created_at}>{fullTimestamp(m.created_at)}</time>
            {m.edited && !m.deleted && <span>· {t("chat.edited")}</span>}
            {m.failed && (
              <button type="button" className={styles.failed} onClick={() => props.onRetry(m)}>
                {t("chat.failed")}
              </button>
            )}
          </div>
        </div>

        {m.reactions.length > 0 && (
          <div className={styles.reactions}>
            {m.reactions.map((r) => (
              <button
                key={r.emoji}
                type="button"
                className={`${styles.reaction} ${r.user_ids.includes(me.id) ? styles.reacted : ""}`}
                onClick={() => props.onReact(m, r.emoji)}
                aria-label={`${r.emoji} ${r.count}`}
              >
                {r.emoji} <span>{r.count}</span>
              </button>
            ))}
          </div>
        )}
        {seen && <span className={styles.seen}>{t("chat.seen")}</span>}
      </div>

      {!m.deleted && !m.pending && (
        <div className={styles.actions}>
          <button type="button" title={t("chat.reply")} aria-label={t("chat.reply")} onClick={() => props.onReply(m)}>
            <FontAwesomeIcon icon={faReply} />
          </button>
          {author && !mine && (
            <button type="button" title={t("chat.mention")} aria-label={t("chat.mention")} onClick={() => props.onMention(author.username)}>
              <FontAwesomeIcon icon={faAt} />
            </button>
          )}
          <button type="button" title={t("chat.react")} aria-label={t("chat.react")} onClick={() => setPicker((p) => !p)}>
            <FontAwesomeIcon icon={faFaceSmile} />
          </button>
          {mine && m.body && (
            <button type="button" title={t("chat.edit")} aria-label={t("chat.edit")} onClick={() => props.onEdit(m)}>
              <FontAwesomeIcon icon={faPen} />
            </button>
          )}
          {(mine || canModerate) && (
            <button type="button" title={t("chat.delete")} aria-label={t("chat.delete")} onClick={() => props.onDelete(m)} className={styles.danger}>
              <FontAwesomeIcon icon={faTrash} />
            </button>
          )}
          {picker && (
            <div className={styles.picker} role="menu">
              {EMOJIS.map((e) => (
                <button
                  key={e}
                  type="button"
                  onClick={() => {
                    setPicker(false);
                    props.onReact(m, e);
                  }}
                >
                  {e}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
});
