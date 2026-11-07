import { useEffect, useState } from "react";
import { t } from "../../i18n";

interface Props {
  /** True while the backend is down or still booting (vs. a real error). */
  starting: boolean;
  retrying: boolean;
  onRetry: () => void;
}

/** Boot screen shown while the API does not answer; the session query polls it. */
export function ServerStarting({ starting, retrying, onRetry }: Props) {
  const [since] = useState(() => Date.now());
  const [now, setNow] = useState(since);

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const elapsed = Math.floor((now - since) / 1000);
  const clock = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, "0")}`;

  return (
    <div className="boot" role="status" aria-live="polite" data-testid="server-starting">
      <div className="bootCard">
        <img src="/braxy-logo.png" alt="" />
        <h1>{starting ? t("boot.starting") : t("boot.error")}</h1>
        <p>{starting ? t("boot.startingText") : t("boot.errorText")}</p>
        {starting && import.meta.env.DEV && elapsed >= 10 && <p className="muted">{t("boot.devHint")}</p>}
        <p className="bootMeta">
          {retrying ? t("boot.checking") : starting ? t("boot.waiting", { time: clock }) : null}
        </p>
        <button className="btn btn-sm" type="button" onClick={onRetry} disabled={retrying}>
          {t("boot.retry")}
        </button>
      </div>
    </div>
  );
}
