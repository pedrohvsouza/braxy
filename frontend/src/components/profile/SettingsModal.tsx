import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useRef, useState } from "react";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys, useMe } from "../../lib/queries";
import type { Me } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import styles from "./Profile.module.css";

type Tab = "profile" | "password" | "prefs";

export function SettingsModal() {
  const close = useUi((s) => s.closeModal);
  const [tab, setTab] = useState<Tab>("profile");
  return (
    <Modal title={t("settings.title")} onClose={close} width={480}>
      <div className={styles.tabs} role="tablist">
        {(["profile", "password", "prefs"] as Tab[]).map((k) => (
          <button key={k} type="button" role="tab" aria-selected={tab === k} className={tab === k ? styles.tabOn : ""} onClick={() => setTab(k)}>
            {t(k === "profile" ? "settings.profileTab" : k === "password" ? "settings.passwordTab" : "settings.prefsTab")}
          </button>
        ))}
      </div>
      {tab === "profile" && <ProfileForm />}
      {tab === "password" && <PasswordForm />}
      {tab === "prefs" && <Prefs />}
    </Modal>
  );
}

function useStatus() {
  const [errors, setErrors] = useState<string[]>([]);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<void>, success: string) => {
    setBusy(true);
    setErrors([]);
    setOk(null);
    try {
      await fn();
      setOk(success);
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };
  return { errors, ok, busy, run };
}

function ProfileForm() {
  const me = useMe();
  const qc = useQueryClient();
  const file = useRef<HTMLInputElement>(null);
  const { errors, ok, busy, run } = useStatus();
  const setMe = (user: Me) => {
    qc.setQueryData(keys.session, { user });
  };

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    void run(async () => {
      const { user } = await api.updateProfile({
        name: String(form.get("name")),
        bio: String(form.get("bio")),
        birthday: String(form.get("birthday")),
      });
      setMe(user);
      void qc.invalidateQueries({ queryKey: ["profile"] });
    }, t("settings.saved"));
  };

  return (
    <form className={styles.form} onSubmit={onSubmit}>
      <div className={styles.avatarRow}>
        <Avatar name={me.name} url={me.avatar_url} size={72} square />
        <button type="button" className="btn btn-sm btn-ghost" onClick={() => file.current?.click()} disabled={busy}>
          {t("settings.changeAvatar")}
        </button>
        <input
          ref={file}
          type="file"
          hidden
          accept="image/png,image/jpeg,image/gif,image/webp"
          onChange={(e) => {
            const f = e.target.files?.[0];
            e.target.value = "";
            if (f) void run(async () => setMe((await api.uploadAvatar(f)).user), t("settings.saved"));
          }}
        />
      </div>
      <label className="field">
        {t("settings.name")}
        <input className="input" name="name" defaultValue={me.name} required minLength={2} maxLength={40} />
      </label>
      <label className="field">
        {t("settings.bio")}
        <textarea className="input" name="bio" defaultValue={me.bio ?? ""} maxLength={140} rows={2} />
      </label>
      <label className="field">
        {t("settings.birthday")}
        <input className="input" name="birthday" type="date" defaultValue={me.birthday ?? ""} max={new Date().toISOString().slice(0, 10)} />
      </label>
      <Feedback errors={errors} ok={ok} />
      <button className="btn" disabled={busy}>
        {t("settings.save")}
      </button>
    </form>
  );
}

function PasswordForm() {
  const { errors, ok, busy, run } = useStatus();
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const el = e.currentTarget;
    const form = new FormData(el);
    void run(async () => {
      await api.changePassword(String(form.get("current")), String(form.get("password")));
      el.reset();
    }, t("settings.passwordChanged"));
  };
  return (
    <form className={styles.form} onSubmit={onSubmit}>
      <label className="field">
        {t("settings.currentPassword")}
        <input className="input" name="current" type="password" autoComplete="current-password" required />
      </label>
      <label className="field">
        {t("settings.newPassword")}
        <input className="input" name="password" type="password" autoComplete="new-password" required minLength={8} />
      </label>
      <Feedback errors={errors} ok={ok} />
      <button className="btn" disabled={busy}>
        {t("settings.changePassword")}
      </button>
    </form>
  );
}

function Prefs() {
  const sound = useUi((s) => s.sound);
  const toggle = useUi((s) => s.toggleSound);
  return (
    <label className={styles.check}>
      <input type="checkbox" checked={sound} onChange={toggle} />
      {t("settings.sound")}
    </label>
  );
}

function Feedback({ errors, ok }: { errors: string[]; ok: string | null }) {
  if (errors.length)
    return (
      <ul className="form-errors" role="alert">
        {errors.map((e) => (
          <li key={e}>{e}</li>
        ))}
      </ul>
    );
  if (ok) return <p className={styles.ok}>{ok}</p>;
  return null;
}
