import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys } from "../../lib/queries";
import styles from "./AuthPage.module.css";
import { FloatingShapes } from "./FloatingShapes";

type State = "checking" | "invalid" | "ready";

/** Landing page of the emailed link: /reset-password?token=… */
export function ResetPasswordPage() {
  const [params] = useSearchParams();
  const token = params.get("token") ?? "";
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [state, setState] = useState<State>(token ? "checking" : "invalid");
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  useEffect(() => {
    if (!token) return;
    let live = true;
    api
      .verifyResetToken(token)
      .then(({ valid }) => live && setState(valid ? "ready" : "invalid"))
      .catch(() => live && setState("ready")); // let the submit report it
    return () => {
      live = false;
    };
  }, [token]);

  const toSignIn = () => navigate("/", { replace: true });

  const onSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const password = String(form.get("password"));
    if (password !== String(form.get("confirm"))) {
      setErrors([t("auth.passwordMismatch")]);
      return;
    }
    setBusy(true);
    setErrors([]);
    try {
      const { user } = await api.resetPassword(token, password);
      qc.setQueryData(keys.session, { user });
      navigate("/", { replace: true });
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={styles.page}>
      <FloatingShapes />
      <div className={styles.resetCard} data-testid="reset-page">
        {state === "checking" && <p className={styles.hint}>{t("auth.resetChecking")}</p>}
        {state === "invalid" && (
          <div className={styles.form}>
            <img src="/braxy-logo.png" alt="" className={styles.formLogo} />
            <h1>{t("auth.resetInvalidTitle")}</h1>
            <p className={styles.hint}>{t("auth.resetInvalidText")}</p>
            <button type="button" className="btn" onClick={toSignIn}>
              {t("auth.backToSignIn")}
            </button>
          </div>
        )}
        {state === "ready" && (
          <form className={styles.form} onSubmit={onSubmit}>
            <img src="/braxy-logo.png" alt="" className={styles.formLogo} />
            <h1>{t("auth.resetTitle")}</h1>
            <p className={styles.hint}>{t("auth.resetText")}</p>
            <input className="input" name="password" type="password" placeholder={t("auth.newPassword")} autoComplete="new-password" required minLength={8} autoFocus />
            <input className="input" name="confirm" type="password" placeholder={t("auth.confirmPassword")} autoComplete="new-password" required minLength={8} />
            {errors.length > 0 && (
              <ul className="form-errors" role="alert">
                {errors.map((x) => (
                  <li key={x}>{x}</li>
                ))}
              </ul>
            )}
            <button className="btn" disabled={busy}>
              {busy ? t("auth.working") : t("auth.resetSave")}
            </button>
            <button type="button" className={styles.forgot} onClick={toSignIn}>
              {t("auth.backToSignIn")}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
