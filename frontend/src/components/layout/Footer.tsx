import { t } from "../../i18n";
import { useUi } from "../../store/ui";
import styles from "./Shell.module.css";

export function Footer() {
  const { connected, everConnected, latency } = useUi();
  let status;
  if (!connected) {
    status = <span className={styles.bad}>{everConnected ? t("footer.reconnecting") : t("footer.connecting")}</span>;
  } else if (latency === null) {
    status = <span>{t("footer.connecting")}</span>;
  } else {
    const [quality, cls] =
      latency < 100 ? [t("footer.perfect"), styles.good] : latency < 250 ? [t("footer.good"), styles.ok] : [t("footer.unstable"), styles.bad];
    const [before, after] = t("footer.connection", { quality: "§", ms: "¤" }).split("§");
    const [mid, end] = after.split("¤");
    status = (
      <span data-testid="latency">
        {before}
        <b className={cls}>{quality}</b>
        {mid}
        <b className={cls}>{latency}</b>
        {end}
      </span>
    );
  }
  return (
    <footer className={styles.footer}>
      {status}
      <span className={styles.copy}>
        {__APP_VERSION__} 2026. {t("footer.madeWith")}{" "}
        <a href="https://github.com/pedrohvsouza/saci" target="_blank" rel="noreferrer">
          Saci
        </a>
      </span>
    </footer>
  );
}
