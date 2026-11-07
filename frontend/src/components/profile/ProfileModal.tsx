import { faCakeCandles, faCalendar } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { t } from "../../i18n";
import { ACHIEVEMENTS, achievementDescription, achievementName } from "../../lib/achievements";
import { api } from "../../lib/api";
import { birthdayLabel, longDate } from "../../lib/format";
import { keys } from "../../lib/queries";
import { levelTier, roleLabel } from "../../lib/roles";
import type { Profile } from "../../lib/types";
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
          <Achievements unlocked={user.achievements ?? []} />
          {user.friendship?.status !== "self" && (
            <button
              type="button"
              className={`btn btn-sm btn-ghost ${styles.blockBtn}`}
              data-testid="block-toggle"
              onClick={async () => {
                if (!user.blocked && !window.confirm(t("profile.blockConfirm", { name: user.name }))) return;
                await (user.blocked ? api.unblock(user.id) : api.block(user.id));
                for (const key of [keys.profile(username), keys.blocks, keys.sidebar, keys.friendships]) {
                  void qc.invalidateQueries({ queryKey: key });
                }
                void qc.invalidateQueries({ queryKey: ["search"] });
              }}
            >
              {user.blocked ? t("profile.unblock") : t("profile.block")}
            </button>
          )}
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

function Achievements({ unlocked }: { unlocked: Profile["achievements"] }) {
  const at = new Map(unlocked.map((a) => [a.key, a.unlocked_at]));
  return (
    <section className={styles.badges} aria-label={t("profile.achievements", { count: at.size, total: ACHIEVEMENTS.length })}>
      <h3>{t("profile.achievements", { count: at.size, total: ACHIEVEMENTS.length })}</h3>
      <ul>
        {ACHIEVEMENTS.map(({ key, icon }) => {
          const won = at.has(key);
          const when = at.get(key);
          const detail = won
            ? `${achievementDescription(key)} ${when ? t("profile.unlockedOn", { date: longDate(when) }) : ""}`.trim()
            : `${t("profile.locked")}: ${achievementDescription(key)}`;
          return (
            <li key={key} className={won ? styles.badgeOn : styles.badgeOff} title={detail} data-testid={`badge-${key}`}>
              <span aria-hidden>{icon}</span>
              <span className="sr-only">
                {achievementName(key)}. {detail}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
