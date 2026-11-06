import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys } from "../../lib/queries";
import styles from "./AuthPage.module.css";
import { FloatingShapes } from "./FloatingShapes";

type Mode = "signin" | "signup";

function Errors({ errors }: { errors: string[] }) {
  if (!errors.length) return null;
  return (
    <ul className="form-errors" role="alert">
      {errors.map((e) => (
        <li key={e}>{e}</li>
      ))}
    </ul>
  );
}

export function AuthPage() {
  const qc = useQueryClient();
  const [mode, setMode] = useState<Mode>("signin");
  const [busy, setBusy] = useState(false);
  const [signinErrors, setSigninErrors] = useState<string[]>([]);
  const [signupErrors, setSignupErrors] = useState<string[]>([]);

  const finish = (user: Awaited<ReturnType<typeof api.login>>["user"]) => {
    qc.setQueryData(keys.session, { user });
  };

  const onSignIn = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    setBusy(true);
    setSigninErrors([]);
    try {
      const { user } = await api.login(String(form.get("login")), String(form.get("password")));
      finish(user);
    } catch (err) {
      setSigninErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };

  const onSignUp = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    setBusy(true);
    setSignupErrors([]);
    try {
      const { user } = await api.signup({
        name: String(form.get("name")),
        username: String(form.get("username")),
        email: String(form.get("email")),
        password: String(form.get("password")),
      });
      finish(user);
    } catch (err) {
      setSignupErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={styles.page}>
      <FloatingShapes />
      <div className={`${styles.card} ${mode === "signup" ? styles.active : ""}`} data-mode={mode}>
        <div className={`${styles.formBox} ${styles.signUp}`} aria-hidden={mode !== "signup"}>
          <form className={styles.form} onSubmit={onSignUp} data-testid="signup-form">
            <h1>{t("auth.signUpTitle")}</h1>
            <input className="input" name="name" placeholder={t("auth.name")} autoComplete="name" required minLength={2} maxLength={40} tabIndex={mode === "signup" ? 0 : -1} />
            <input className="input" name="username" placeholder={t("auth.username")} autoComplete="username" required pattern="@?[A-Za-z0-9_]{3,20}" title="3 a 20 letras, números ou _" tabIndex={mode === "signup" ? 0 : -1} />
            <input className="input" name="email" type="email" placeholder={t("auth.email")} autoComplete="email" required tabIndex={mode === "signup" ? 0 : -1} />
            <input className="input" name="password" type="password" placeholder={t("auth.password")} autoComplete="new-password" required minLength={8} tabIndex={mode === "signup" ? 0 : -1} />
            <Errors errors={signupErrors} />
            <button className="btn" disabled={busy} tabIndex={mode === "signup" ? 0 : -1}>
              {busy ? t("auth.working") : t("auth.signUp")}
            </button>
          </form>
        </div>

        <div className={`${styles.formBox} ${styles.signIn}`} aria-hidden={mode !== "signin"}>
          <form className={styles.form} onSubmit={onSignIn} data-testid="signin-form">
            <img src="/braxy-logo.png" alt="" className={styles.formLogo} />
            <h1>{t("auth.signInTitle")}</h1>
            <input className="input" name="login" placeholder={t("auth.login")} autoComplete="username" required tabIndex={mode === "signin" ? 0 : -1} />
            <input className="input" name="password" type="password" placeholder={t("auth.password")} autoComplete="current-password" required tabIndex={mode === "signin" ? 0 : -1} />
            <span className={styles.forgot} title={t("auth.forgotSoon")} aria-disabled="true">
              {t("auth.forgot")}
            </span>
            <Errors errors={signinErrors} />
            <button className="btn" disabled={busy} tabIndex={mode === "signin" ? 0 : -1}>
              {busy ? t("auth.working") : t("auth.signIn")}
            </button>
          </form>
        </div>

        <div className={styles.overlayBox}>
          <div className={styles.overlay}>
            <div className={`${styles.panel} ${styles.panelLeft}`}>
              <img src="/braxy-logo.png" alt="" className={styles.eagle} />
              <h2>{t("auth.welcomeBack")}</h2>
              <p>{t("auth.welcomeBackText")}</p>
              <button className={styles.ghost} type="button" onClick={() => setMode("signin")} tabIndex={mode === "signup" ? 0 : -1}>
                {t("auth.toSignIn")}
              </button>
            </div>
            <div className={`${styles.panel} ${styles.panelRight}`}>
              <img src="/braxy-logo.png" alt="" className={styles.eagle} />
              <h2>{t("auth.hello")}</h2>
              <p>{t("auth.helloText")}</p>
              <button className={styles.ghost} type="button" onClick={() => setMode("signup")} tabIndex={mode === "signin" ? 0 : -1}>
                {t("auth.toSignUp")}
              </button>
            </div>
          </div>
        </div>
      </div>
      <p className={styles.brand}>BRAXY</p>
    </div>
  );
}
