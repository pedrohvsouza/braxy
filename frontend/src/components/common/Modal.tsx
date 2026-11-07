import { faXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { type ReactNode, useEffect, useId, useRef } from "react";
import { t } from "../../i18n";
import styles from "./common.module.css";
import { useFocusTrap } from "./focus";

interface Props {
  title: string;
  onClose: () => void;
  children: ReactNode;
  width?: number;
}

export function Modal({ title, onClose, children, width = 440 }: Props) {
  const box = useRef<HTMLDivElement>(null);
  const titleId = useId();
  useFocusTrap(box);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className={styles.backdrop} onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div ref={box} className={styles.modal} style={{ maxWidth: width }} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}>
        <header className={styles.modalHeader}>
          <h2 id={titleId}>{title}</h2>
          <button className="icon-btn" onClick={onClose} aria-label={t("common.close")} type="button">
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </header>
        <div className={styles.modalBody}>{children}</div>
      </div>
    </div>
  );
}
