import { type ReactNode, useEffect, useRef, useState } from "react";
import styles from "./common.module.css";
import { focusables, onMenuKey } from "./focus";

interface Props {
  trigger: (open: boolean) => ReactNode;
  children: (close: () => void) => ReactNode;
  align?: "left" | "right";
  label: string;
  /** Free content (Tab moves through it) instead of a list of menu items. */
  panel?: boolean;
}

/** Click-to-open menu that closes on outside click / Escape. */
export function Dropdown({ trigger, children, align = "right", label, panel = false }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const trigger_ = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    // Opening moves focus to the first item (keyboard and screen readers).
    const menu = ref.current?.querySelector<HTMLElement>("[data-dropdown-body]");
    if (menu) (panel ? (focusables(menu)[0] ?? menu) : menu.querySelector<HTMLElement>('[role="menuitem"]'))?.focus();
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        trigger_.current?.focus();
      } else if (e.key === "Tab" && !panel) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, panel]);

  return (
    <div className={styles.dropdown} ref={ref}>
      <button
        ref={trigger_}
        type="button"
        className={styles.dropdownTrigger}
        onClick={() => setOpen((o) => !o)}
        aria-haspopup={panel ? "dialog" : "menu"}
        aria-expanded={open}
        aria-label={label}
        title={label}
      >
        {trigger(open)}
      </button>
      {open && (
        <div className={`${styles.menu} ${align === "left" ? styles.menuLeft : ""}`} role={panel ? "dialog" : "menu"} aria-label={label} onKeyDown={panel ? undefined : onMenuKey} tabIndex={-1} data-dropdown-body>
          {children(() => setOpen(false))}
        </div>
      )}
    </div>
  );
}

export function MenuItem({ icon, children, onClick, danger }: { icon?: ReactNode; children: ReactNode; onClick: () => void; danger?: boolean }) {
  return (
    <button type="button" role="menuitem" tabIndex={-1} className={`${styles.menuItem} ${danger ? styles.danger : ""}`} onClick={onClick}>
      {icon && <span className={styles.menuIcon}>{icon}</span>}
      {children}
    </button>
  );
}
