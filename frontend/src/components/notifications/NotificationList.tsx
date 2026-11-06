import {
  faArrowUpRightDots, faAt, faCheck, faReply, faUserGroup, faUserPlus, type IconDefinition,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { shortTime } from "../../lib/format";
import { notificationText } from "../../lib/notificationText";
import { keys, useNotifications } from "../../lib/queries";
import type { AppNotification, NotificationKind, NotificationsData } from "../../lib/types";
import { useUi } from "../../store/ui";
import styles from "./Notifications.module.css";

const ICON: Record<NotificationKind, IconDefinition> = {
  friend_request: faUserPlus,
  friend_accepted: faCheck,
  mention: faAt,
  reply: faReply,
  level_up: faArrowUpRightDots,
  group_added: faUserGroup,
};

export function useOpenNotification() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const openModal = useUi((s) => s.openModal);
  return (n: AppNotification) => {
    if (!n.read) {
      void api.readNotification(n.id).then(({ unread_count }) =>
        qc.setQueryData<NotificationsData>(keys.notifications, (d) =>
          d && { unread_count, notifications: d.notifications.map((x) => (x.id === n.id ? { ...x, read: true } : x)) },
        ),
      );
    }
    if (n.kind === "friend_request") openModal({ kind: "requests" });
    else if (n.kind === "friend_accepted" && n.actor) openModal({ kind: "profile", username: n.actor.username });
    else if (n.conversation_id) navigate(`/c/${n.conversation_id}`);
  };
}

export function NotificationList({ onNavigate }: { onNavigate: () => void }) {
  const qc = useQueryClient();
  const { data } = useNotifications();
  const open = useOpenNotification();

  const readAll = async () => {
    await api.readAllNotifications();
    qc.setQueryData<NotificationsData>(keys.notifications, (d) =>
      d && { unread_count: 0, notifications: d.notifications.map((x) => ({ ...x, read: true })) },
    );
  };

  return (
    <div className={styles.panel}>
      <header>
        <strong>{t("notif.title")}</strong>
        {(data?.unread_count ?? 0) > 0 && (
          <button type="button" onClick={readAll}>
            {t("notif.readAll")}
          </button>
        )}
      </header>
      <div className={styles.list}>
        {data?.notifications.length === 0 && <p className={styles.empty}>{t("notif.empty")}</p>}
        {data?.notifications.map((n) => (
          <button
            key={n.id}
            type="button"
            className={`${styles.item} ${n.read ? "" : styles.unread}`}
            onClick={() => {
              onNavigate();
              open(n);
            }}
          >
            <span className={`${styles.icon} ${styles[n.kind]}`}>
              <FontAwesomeIcon icon={ICON[n.kind]} />
            </span>
            <span className={styles.text}>{notificationText(n)}</span>
            <span className={styles.time}>{shortTime(n.created_at)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
