import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys } from "../../lib/queries";
import type { MessageKey } from "../../i18n/pt-BR";
import type { SanctionKind, UserSummary } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import { UserName } from "../common/UserName";
import styles from "./Moderation.module.css";

const DURATIONS: { minutes: number | undefined; label: MessageKey }[] = [
  { minutes: 10, label: "mod.minutes10" },
  { minutes: 60, label: "mod.hour1" },
  { minutes: 1440, label: "mod.hours24" },
  { minutes: 10080, label: "mod.days7" },
  { minutes: undefined, label: "mod.forever" },
];

/** Mute (with a duration) or ban a member of a conversation. */
export function ModerateModal({ conversationId, user }: { conversationId: number; user: UserSummary }) {
  const close = useUi((s) => s.closeModal);
  const pushToast = useUi((s) => s.pushToast);
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const apply = async (kind: SanctionKind, minutes?: number) => {
    if (kind === "ban" && !window.confirm(t("mod.banConfirm", { name: user.name }))) return;
    setBusy(true);
    setErrors([]);
    try {
      await api.sanction(conversationId, user.id, kind, minutes);
      void qc.invalidateQueries({ queryKey: keys.sanctions(conversationId) });
      pushToast({ text: t("mod.done") });
      close();
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={t("mod.title", { name: user.name })} onClose={close} width={420}>
      <div className={styles.box} data-testid="moderate-modal">
        <div className={styles.who}>
          <Avatar name={user.name} url={user.avatar_url} size={40} />
          <div>
            <UserName name={user.name} role={user.role} level={user.level} />
            <span className="muted">@{user.username}</span>
          </div>
        </div>

        <h3>{t("mod.mute")}</h3>
        <p className="muted">{t("mod.muteText")}</p>
        <div className={styles.durations}>
          {DURATIONS.map((d) => (
            <button key={d.label} type="button" className="btn btn-sm btn-ghost" disabled={busy} onClick={() => void apply("mute", d.minutes)}>
              {t(d.label)}
            </button>
          ))}
        </div>

        <h3>{t("mod.ban")}</h3>
        <p className="muted">{t("mod.banText")}</p>
        <button type="button" className="btn btn-sm btn-danger" disabled={busy} onClick={() => void apply("ban")}>
          {t("mod.ban")}
        </button>

        {errors.length > 0 && (
          <ul className="form-errors" role="alert">
            {errors.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        )}
      </div>
    </Modal>
  );
}
