import { faXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useEffect } from "react";
import { t } from "../../i18n";
import { type Toast, useUi } from "../../store/ui";
import { useOpenNotification } from "./NotificationList";
import styles from "./Notifications.module.css";

const DURATION = 5000;

function ToastCard({ toast }: { toast: Toast }) {
  const dismiss = useUi((s) => s.dismissToast);
  const open = useOpenNotification();
  useEffect(() => {
    const id = window.setTimeout(() => dismiss(toast.id), DURATION);
    return () => window.clearTimeout(id);
  }, [toast.id, dismiss]);
  return (
    <div className={styles.toast} role="status" data-testid="toast">
      <button type="button" className={styles.toastClose} onClick={() => dismiss(toast.id)} aria-label={t("common.close")}>
        <FontAwesomeIcon icon={faXmark} />
      </button>
      <button
        type="button"
        className={styles.toastBody}
        onClick={() => {
          dismiss(toast.id);
          if (toast.notification) open(toast.notification);
        }}
      >
        {toast.text}
      </button>
      <span className={styles.toastBar} style={{ animationDuration: `${DURATION}ms` }} />
    </div>
  );
}

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
  return (
    <div className={styles.toasts}>
      {toasts.map((toast) => (
        <ToastCard key={toast.id} toast={toast} />
      ))}
    </div>
  );
}
