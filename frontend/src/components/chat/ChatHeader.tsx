import { faCircleInfo, faUserGroup, faUsers } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { t } from "../../i18n";
import type { ConversationDetail, Me } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Chat.module.css";

export function ChatHeader({ convo, me, online }: { convo: ConversationDetail; me: Me; online: boolean }) {
  const openModal = useUi((s) => s.openModal);
  const other = convo.kind === "dm" ? convo.members.find((m) => m.user.id !== me.id)?.user : undefined;

  return (
    <header className={styles.header}>
      {other ? (
        <>
          <button type="button" className={styles.headerAvatar} onClick={() => openModal({ kind: "profile", username: other.username })}>
            <Avatar name={other.name} url={other.avatar_url} size={46} online={online} />
          </button>
          <div className={styles.headerText}>
            <UserName name={other.name} role={other.role} level={other.level} onClick={() => openModal({ kind: "profile", username: other.username })} />
            <span className={styles.sub}>{online ? t("chat.online") : t("chat.offline")}</span>
          </div>
        </>
      ) : (
        <>
          {convo.avatar_url ? (
            <Avatar name={convo.name ?? "Grupo"} url={convo.avatar_url} size={46} />
          ) : (
            <span className={styles.headerIcon}>
              <FontAwesomeIcon icon={convo.kind === "lobby" ? faUsers : faUserGroup} />
            </span>
          )}
          <div className={styles.headerText}>
            <strong className={convo.kind === "lobby" ? styles.lobbyTitle : undefined}>{convo.name}</strong>
            <span className={styles.sub}>{t("chat.members", { count: convo.member_count })}</span>
          </div>
          <button
            type="button"
            className="icon-btn"
            style={{ marginLeft: "auto" }}
            onClick={() => openModal({ kind: "groupInfo", conversationId: convo.id })}
            aria-label={t("chat.info")}
            title={t("chat.info")}
          >
            <FontAwesomeIcon icon={faCircleInfo} />
          </button>
        </>
      )}
    </header>
  );
}
