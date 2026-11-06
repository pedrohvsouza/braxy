import { faCakeCandles, faCalendar } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { birthdayLabel, longDate } from "../../lib/format";
import { keys } from "../../lib/queries";
import { levelTier, roleLabel } from "../../lib/roles";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import { UserName } from "../common/UserName";
import { FriendAction } from "../sidebar/SearchResults";
import styles from "./Profile.module.css";

export function ProfileModal({ username }: { username: string }) {
  const close = useUi((s) => s.closeModal);
  const qc = useQueryClient();
  const { data: user, error } = useQuery({
    queryKey: keys.profile(username),
    queryFn: () => api.profile(username).then((r) => r.user),
  });

  return (
    <Modal title={t("profile.title")} onClose={close} width={400}>
      {error && <p className="muted">{t("common.error")}</p>}
      {user && (
        <div className={styles.card} data-testid="profile-card">
          <div className={styles.banner} />
          <div className={styles.avatar}>
            <Avatar name={user.name} url={user.avatar_url} size={96} online={user.friendship?.status === "friends" ? user.online : null} />
          </div>
          <UserName name={user.name} role={user.role} className={styles.name} showRole={false} />
          <span className="muted">@{user.username}</span>
          <div className={styles.chips}>
            <span className={styles.chip}>{roleLabel(user.role)}</span>
            <span className={`${styles.chip} level ${levelTier(user.level)}`}>{t("profile.level", { level: user.level })}</span>
          </div>
          <p className={styles.bio}>{user.bio || t("profile.noBio")}</p>
          <ul className={styles.facts}>
            <li>
              <FontAwesomeIcon icon={faCalendar} /> {t("profile.joined", { date: longDate(user.joined_at) })}
            </li>
            {user.birthday && (
              <li>
                <FontAwesomeIcon icon={faCakeCandles} /> {t("profile.birthday", { date: birthdayLabel(user.birthday) })}
              </li>
            )}
          </ul>
          {user.friendship && user.friendship.status !== "self" && (
            <div className={styles.buttons}>
              <FriendAction result={{ user, friendship: user.friendship }} onDone={close} />
              {user.friendship.id && user.friendship.status !== "none" && (
                <button
                  type="button"
                  className="btn btn-sm btn-ghost"
                  onClick={async () => {
                    await api.removeFriendship(user.friendship!.id!);
                    void qc.invalidateQueries({ queryKey: keys.profile(username) });
                    void qc.invalidateQueries({ queryKey: keys.sidebar });
                    void qc.invalidateQueries({ queryKey: keys.friendships });
                  }}
                >
                  {user.friendship.status === "friends"
                    ? t("friend.remove")
                    : user.friendship.status === "incoming"
                      ? t("friend.decline")
                      : t("friend.cancel")}
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
