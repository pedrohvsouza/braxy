import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys, useSidebar } from "../../lib/queries";
import { useUi } from "../../store/ui";
import { Modal } from "../common/Modal";
import { FriendPicker } from "./FriendPicker";
import styles from "./Groups.module.css";

export function CreateGroupModal() {
  const close = useUi((s) => s.closeModal);
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { data } = useSidebar();
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  const toggle = (id: number) =>
    setSelected((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const onSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const name = String(new FormData(e.currentTarget).get("name"));
    setBusy(true);
    setErrors([]);
    try {
      const { conversation } = await api.createGroup(name, [...selected]);
      await qc.invalidateQueries({ queryKey: keys.sidebar });
      close();
      navigate(`/c/${conversation.id}`);
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={t("group.createTitle")} onClose={close}>
      <form className={styles.form} onSubmit={onSubmit}>
        <label className="field">
          {t("group.name")}
          <input className="input" name="name" required minLength={2} maxLength={40} autoFocus />
        </label>
        <span className="field">{t("group.pickFriends")}</span>
        <FriendPicker friends={data?.friends ?? []} selected={selected} onToggle={toggle} />
        {errors.length > 0 && (
          <ul className="form-errors">
            {errors.map((x) => (
              <li key={x}>{x}</li>
            ))}
          </ul>
        )}
        <button className="btn" disabled={busy}>
          {t("group.create")}
        </button>
      </form>
    </Modal>
  );
}
