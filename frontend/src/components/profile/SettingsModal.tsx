import { useQuery, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useEffect, useRef, useState } from "react";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import {
  notifyPermission, type NotifyPermission, requestNotifyPermission, showDesktopNotification,
} from "../../lib/desktopNotify";
import { disablePush, enablePush, pushEnabled, pushKey, pushSupported } from "../../lib/push";
import { keys, useMe } from "../../lib/queries";
import type { Me } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import styles from "./Profile.module.css";

type Tab = "profile" | "password" | "prefs" | "blocked";

const TAB_LABELS = {
  profile: "settings.profileTab",
  password: "settings.passwordTab",
  prefs: "settings.prefsTab",
  blocked: "settings.blockedTab",
} as const;

export function SettingsModal() {
  const close = useUi((s) => s.closeModal);
  const [tab, setTab] = useState<Tab>("profile");
  return (
    <Modal title={t("settings.title")} onClose={close} width={480}>
      <div className={styles.tabs} role="tablist">
        {(Object.keys(TAB_LABELS) as Tab[]).map((k) => (
          <button key={k} type="button" role="tab" aria-selected={tab === k} className={tab === k ? styles.tabOn : ""} onClick={() => setTab(k)}>
            {t(TAB_LABELS[k])}
          </button>
        ))}
      </div>
      {tab === "profile" && <ProfileForm />}
      {tab === "password" && <PasswordForm />}
      {tab === "prefs" && <Prefs />}
      {tab === "blocked" && <Blocked />}
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
  const desktop = useUi((s) => s.desktopNotify);
  const setDesktop = useUi((s) => s.setDesktopNotify);
  const [permission, setPermission] = useState<NotifyPermission>(notifyPermission);
  const enabled = desktop && permission === "granted";

  const onDesktop = async (on: boolean) => {
    if (!on) return setDesktop(false);
    const next = permission === "granted" ? permission : await requestNotifyPermission();
    setPermission(next);
    setDesktop(next === "granted");
    if (next === "granted") {
      showDesktopNotification({ title: "Braxy", body: t("settings.notifyTest"), tag: "braxy-test" });
    }
  };

  return (
    <div className={styles.form}>
      <label className={styles.check}>
        <input type="checkbox" checked={sound} onChange={toggle} />
        {t("settings.sound")}
      </label>
      <label className={styles.check}>
        <input
          type="checkbox"
          checked={enabled}
          disabled={permission === "unsupported" || permission === "denied"}
          onChange={(e) => void onDesktop(e.target.checked)}
        />
        {t("settings.desktopNotify")}
      </label>
      {permission === "denied" && <p className={styles.hint}>{t("settings.notifyDenied")}</p>}
      {permission === "unsupported" && <p className={styles.hint}>{t("settings.notifyUnsupported")}</p>}
      <PushPref permission={permission} onPermission={setPermission} />
    </div>
  );
}

/** Web Push with Braxy closed; shown only when the server has a VAPID key. */
function PushPref({ permission, onPermission }: { permission: NotifyPermission; onPermission: (p: NotifyPermission) => void }) {
  const [key, setKey] = useState<string | null>(null);
  const [on, setOn] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!pushSupported()) return;
    let live = true;
    void pushKey().then((k) => live && setKey(k));
    void pushEnabled().then((v) => live && setOn(v));
    return () => {
      live = false;
    };
  }, []);

  if (!key) return null;

  const toggle = async (next: boolean) => {
    setBusy(true);
    setError(null);
    try {
      if (next) {
        const granted = permission === "granted" ? permission : await requestNotifyPermission();
        onPermission(granted);
        if (granted !== "granted") return;
        await enablePush(key);
      } else {
        await disablePush();
      }
      setOn(next);
    } catch {
      setError(t("settings.pushFailed"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <label className={styles.check}>
        <input type="checkbox" checked={on} disabled={busy || permission === "denied"} onChange={(e) => void toggle(e.target.checked)} />
        {t("settings.push")}
      </label>
      {error && <p className={styles.hint}>{error}</p>}
    </>
  );
}

function Blocked() {
  const qc = useQueryClient();
  const { data } = useQuery({ queryKey: keys.blocks, queryFn: api.blocks });
  if (!data) return <p className="muted">{t("common.loading")}</p>;
  if (!data.users.length) return <p className="muted">{t("settings.noBlocked")}</p>;
  return (
    <ul className={styles.blockedList} data-testid="blocked-list">
      {data.users.map((u) => (
        <li key={u.id}>
          <Avatar name={u.name} url={u.avatar_url} size={32} />
          <span>
            {u.name} <span className="muted">@{u.username}</span>
          </span>
          <button
            type="button"
            className="btn btn-sm btn-ghost"
            onClick={async () => {
              await api.unblock(u.id);
              void qc.invalidateQueries({ queryKey: keys.blocks });
              void qc.invalidateQueries({ queryKey: ["profile"] });
            }}
          >
            {t("profile.unblock")}
          </button>
        </li>
      ))}
    </ul>
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
