import { useQueryClient } from "@tanstack/react-query";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { keys, useFriendships } from "../../lib/queries";
import type { FriendRequest } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import { UserName } from "../common/UserName";
import styles from "../groups/Groups.module.css";

export function RequestsModal() {
  const close = useUi((s) => s.closeModal);
  const openModal = useUi((s) => s.openModal);
  const qc = useQueryClient();
  const { data } = useFriendships();
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: keys.friendships });
    void qc.invalidateQueries({ queryKey: keys.sidebar });
  };

  const Row = ({ r, incoming }: { r: FriendRequest; incoming: boolean }) => (
    <div className={styles.member} data-testid={`request-${r.user.username}`}>
      <button type="button" className={styles.memberMain} onClick={() => openModal({ kind: "profile", username: r.user.username })}>
        <Avatar name={r.user.name} url={r.user.avatar_url} size={34} />
        <UserName name={r.user.name} role={r.user.role} level={r.user.level} />
      </button>
      {incoming && (
        <button type="button" className="btn btn-sm" onClick={() => api.acceptFriend(r.id).then(refresh)}>
          {t("friend.accept")}
        </button>
      )}
      <button type="button" className="btn btn-sm btn-ghost" onClick={() => api.removeFriendship(r.id).then(refresh)}>
        {incoming ? t("friend.decline") : t("friend.cancel")}
      </button>
    </div>
  );

  const incoming = data?.incoming ?? [];
  const outgoing = data?.outgoing ?? [];
  return (
    <Modal title={t("friend.requestsTitle")} onClose={close}>
      <div className={styles.form}>
        {!incoming.length && !outgoing.length && <p className="muted">{t("friend.none")}</p>}
        {incoming.length > 0 && <h3 className={styles.subTitle}>{t("friend.incoming")}</h3>}
        {incoming.map((r) => (
          <Row key={r.id} r={r} incoming />
        ))}
        {outgoing.length > 0 && <h3 className={styles.subTitle}>{t("friend.outgoing")}</h3>}
        {outgoing.map((r) => (
          <Row key={r.id} r={r} incoming={false} />
        ))}
      </div>
    </Modal>
  );
}
