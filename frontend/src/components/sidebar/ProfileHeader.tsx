import { t } from "../../i18n";
import { thousands } from "../../lib/format";
import { useMe } from "../../lib/queries";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Sidebar.module.css";

export function ProfileHeader() {
  const me = useMe();
  const openModal = useUi((s) => s.openModal);
  const pct = me.level_need ? Math.min(100, Math.floor((me.level_xp / me.level_need) * 100)) : 0;
  return (
    <div className={styles.me}>
      <button className={styles.meAvatar} onClick={() => openModal({ kind: "settings" })} type="button" aria-label={t("top.settings")}>
        <Avatar name={me.name} url={me.avatar_url} size={58} square />
      </button>
      <div className={styles.meInfo}>
        <UserName name={me.name} role={me.role} level={me.level} showRole={false} onClick={() => openModal({ kind: "profile", username: me.username })} />
        <span className={styles.xpText} data-testid="xp-text">
          {t("level.progress", { into: thousands(me.level_xp), need: thousands(me.level_need), next: me.level + 1 })}
        </span>
        <div className={styles.xpBar} role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
          <div className={styles.xpFill} style={{ width: `${Math.max(pct, 2)}%` }} />
          <span>{pct}%</span>
        </div>
      </div>
    </div>
  );
}
