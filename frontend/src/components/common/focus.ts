import { type KeyboardEvent as ReactKeyboardEvent, type RefObject, useEffect } from "react";

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function focusables(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => !el.hidden && el.getAttribute("aria-hidden") !== "true");
}

/**
 * Dialog focus: moves focus inside on mount (the first field, else the first
 * control), keeps Tab cycling inside, and gives focus back on unmount.
 */
export function useFocusTrap(ref: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const before = document.activeElement as HTMLElement | null;
    const all = focusables(root);
    const field = all.find((el) => el.matches("input, textarea, select"));
    // Prefer content over the header's close button.
    (field ?? all.find((el) => !el.closest("header")) ?? all[0] ?? root).focus();

    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Tab") return;
      const items = focusables(root);
      if (!items.length) {
        e.preventDefault();
        return;
      }
      const first = items[0];
      const last = items[items.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || !root.contains(active))) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && (active === last || !root.contains(active))) {
        e.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      if (before && document.contains(before)) before.focus();
    };
  }, [ref]);
}

/** Arrow/Home/End movement between the `[role=menuitem]` children of a menu. */
export function onMenuKey(e: ReactKeyboardEvent<HTMLElement>): void {
  const items = [...e.currentTarget.querySelectorAll<HTMLElement>('[role="menuitem"]')];
  const i = items.indexOf(document.activeElement as HTMLElement);
  const next =
    e.key === "ArrowDown" || e.key === "ArrowRight" ? i + 1
    : e.key === "ArrowUp" || e.key === "ArrowLeft" ? i - 1
    : e.key === "Home" ? 0
    : e.key === "End" ? items.length - 1
    : null;
  if (next === null || !items.length) return;
  e.preventDefault();
  items[(next + items.length) % items.length].focus();
}
