import { faCrown } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys, useConversation, useMe, useSidebar } from "../../lib/queries";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import { UserName } from "../common/UserName";
import { FriendPicker } from "./FriendPicker";
import styles from "./Groups.module.css";

export function GroupInfoModal({ conversationId }: { conversationId: number }) {
  const close = useUi((s) => s.closeModal);
  const openModal = useUi((s) => s.openModal);
  const me = useMe();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { data: convo } = useConversation(conversationId);
  const { data: sidebar } = useSidebar();
  const [adding, setAdding] = useState(false);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [errors, setErrors] = useState<string[]>([]);
  const file = useRef<HTMLInputElement>(null);

  if (!convo) return null;
  const memberIds = new Set(convo.members.map((m) => m.user.id));
  const candidates = (sidebar?.friends ?? []).filter((f) => !memberIds.has(f.user.id));
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: keys.conversation(conversationId) });
    void qc.invalidateQueries({ queryKey: keys.sidebar });
  };
  const guard = async (fn: () => Promise<unknown>) => {
    setErrors([]);
    try {
      await fn();
      refresh();
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    }
  };

  const rename = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const name = String(new FormData(e.currentTarget).get("name"));
    void guard(() => api.renameGroup(conversationId, name));
  };

  const members = [...convo.members].sort((a, b) => (a.role === "owner" ? -1 : b.role === "owner" ? 1 : Number(b.online) - Number(a.online)));

  return (
    <Modal title={t("group.infoTitle")} onClose={close} width={460}>
      <div className={styles.form}>
        <div className={styles.groupTop}>
          <Avatar name={convo.name ?? "Grupo"} url={convo.avatar_url} size={64} group />
          {convo.can_manage ? (
            <form className={styles.renameForm} onSubmit={rename}>
              <input className="input" name="name" defaultValue={convo.name ?? ""} minLength={2} maxLength={40} required />
              <button className="btn btn-sm">{t("group.rename")}</button>
            </form>
          ) : (
            <strong className={styles.groupTitle}>{convo.name}</strong>
          )}
        </div>
        {convo.can_manage && (
          <div className={styles.row}>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => file.current?.click()}>
              {t("group.changeAvatar")}
            </button>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => setAdding((a) => !a)}>
              {t("group.addMembers")}
            </button>
            <input
              ref={file}
              type="file"
              hidden
              accept="image/png,image/jpeg,image/gif,image/webp"
              onChange={(e) => {
                const f = e.target.files?.[0];
                e.target.value = "";
                if (f) void guard(() => api.uploadGroupAvatar(conversationId, f));
              }}
            />
          </div>
        )}
        {adding && (
          <div className={styles.addBox}>
            <FriendPicker
              friends={candidates}
              selected={selected}
              onToggle={(id) =>
                setSelected((s) => {
                  const next = new Set(s);
                  if (next.has(id)) next.delete(id);
                  else next.add(id);
                  return next;
                })
              }
            />
            {candidates.length > 0 && (
              <button
                type="button"
                className="btn btn-sm"
                disabled={!selected.size}
                onClick={() =>
                  void guard(async () => {
                    await api.addMembers(conversationId, [...selected]);
                    setSelected(new Set());
                    setAdding(false);
                  })
                }
              >
                {t("group.addMembers")}
              </button>
            )}
          </div>
        )}
        {errors.length > 0 && (
          <ul className="form-errors">
            {errors.map((x) => (
              <li key={x}>{x}</li>
            ))}
          </ul>
        )}
        <h3 className={styles.subTitle}>
          {t("group.membersTitle")} · {convo.member_count}
        </h3>
        <div className={styles.members}>
          {members.slice(0, 200).map((m) => (
            <div key={m.user.id} className={styles.member}>
              <button type="button" className={styles.memberMain} onClick={() => openModal({ kind: "profile", username: m.user.username })}>
                <Avatar name={m.user.name} url={m.user.avatar_url} size={34} online={m.online} />
                <UserName name={m.user.name} role={m.user.role} level={m.user.level} />
                {m.role === "owner" && <FontAwesomeIcon icon={faCrown} className={styles.crown} title={t("group.owner")} />}
              </button>
              {convo.can_manage && m.role !== "owner" && (
                <button type="button" className="btn btn-sm btn-ghost" onClick={() => void guard(() => api.removeMember(conversationId, m.user.id))}>
                  {t("group.remove")}
                </button>
              )}
            </div>
          ))}
        </div>
        {convo.kind === "group" && !convo.can_manage && (
          <button
            type="button"
            className="btn btn-danger"
            onClick={() => {
              if (!window.confirm(t("group.leaveConfirm"))) return;
              void guard(async () => {
                await api.removeMember(conversationId, me.id);
                close();
                navigate("/");
              });
            }}
          >
            {t("group.leave")}
          </button>
        )}
      </div>
    </Modal>
  );
}
