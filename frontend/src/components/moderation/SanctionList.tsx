import { useQueryClient } from "@tanstack/react-query";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { longDate } from "../../lib/format";
import { keys, useSanctions } from "../../lib/queries";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Moderation.module.css";

/** Active mutes and bans of a conversation, for its moderators. */
export function SanctionList({ conversationId }: { conversationId: number }) {
  const qc = useQueryClient();
  const { data } = useSanctions(conversationId, true);

  const lift = async (userId: number, kind: "mute" | "ban") => {
    await api.liftSanction(conversationId, userId, kind);
    void qc.invalidateQueries({ queryKey: keys.sanctions(conversationId) });
    void qc.invalidateQueries({ queryKey: ["members", conversationId] });
  };

  return (
    <section className={styles.sanctions} data-testid="sanction-list">
      <h3>{t("mod.active")}</h3>
      {data && data.length === 0 && <p className="muted">{t("mod.none")}</p>}
      {data?.map((s) => (
        <div key={`${s.user.id}-${s.kind}`} className={styles.sanction}>
          <Avatar name={s.user.name} url={s.user.avatar_url} size={30} />
          <div className={styles.sanctionText}>
            <UserName name={s.user.name} role={s.user.role} level={s.user.level} />
            <span className="muted">
              {s.kind === "mute" ? t("mod.muted") : t("mod.banned")} ·{" "}
              {s.expires_at ? t("mod.until", { date: longDate(s.expires_at) }) : t("mod.untilLifted")}
            </span>
          </div>
          <button type="button" className="btn btn-sm btn-ghost" onClick={() => void lift(s.user.id, s.kind)}>
            {t("mod.lift")}
          </button>
        </div>
      ))}
    </section>
  );
}
