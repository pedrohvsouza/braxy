import { faComments, faUserGroup, faUsers, faWifi } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { t } from "../../i18n";
import { compactNumber } from "../../lib/format";
import { useStats } from "../../lib/queries";
import { FloatingShapes } from "../auth/FloatingShapes";
import styles from "./EmptyState.module.css";

export function EmptyState() {
  const { data: stats } = useStats();
  const cards = [
    { key: "users", icon: faUsers, value: stats?.users, label: t("stats.users") },
    { key: "messages", icon: faComments, value: stats?.messages, label: t("stats.messages") },
    { key: "online", icon: faWifi, value: stats?.online, label: t("stats.online") },
    { key: "groups", icon: faUserGroup, value: stats?.groups, label: t("stats.groups") },
  ];
  return (
    <section className={styles.empty}>
      <FloatingShapes density={0.5} />
      <div className={styles.hero}>
        <div className={styles.blob}>
          <img src="/braxy-logo.png" alt="Braxy" className={styles.eagle} />
        </div>
        <h1>{t("empty.title")}</h1>
        <p className={styles.subtitle}>{t("empty.subtitle")}</p>
        <p className={styles.body}>{t("empty.body")}</p>
      </div>
      <div className={styles.stats} data-testid="stats">
        {cards.map((c) => (
          <div key={c.key} className={styles.stat} data-testid={`stat-${c.key}`}>
            <strong>{c.value === undefined ? "—" : compactNumber(c.value)}</strong>
            <span>
              {c.label} <FontAwesomeIcon icon={c.icon} />
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}
