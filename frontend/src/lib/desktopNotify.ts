// Native browser notifications (Notification API) for when Braxy is in the
// background. Opt-in from Settings; the browser's permission is asked then.

export type NotifyPermission = NotificationPermission | "unsupported";

export function notifyPermission(): NotifyPermission {
  return typeof window !== "undefined" && "Notification" in window ? Notification.permission : "unsupported";
}

export async function requestNotifyPermission(): Promise<NotifyPermission> {
  if (notifyPermission() === "unsupported") return "unsupported";
  try {
    return await Notification.requestPermission();
  } catch {
    return Notification.permission;
  }
}

/** Whether the user is looking at Braxy right now. */
export function appInFocus(): boolean {
  return !document.hidden && document.hasFocus();
}

interface Options {
  title: string;
  body: string;
  icon?: string | null;
  /** Same tag replaces the previous notification instead of stacking. */
  tag: string;
  silent?: boolean;
  onClick?: () => void;
}

export function showDesktopNotification({ title, body, icon, tag, silent, onClick }: Options): void {
  if (notifyPermission() !== "granted") return;
  try {
    const n = new Notification(title, {
      body: body.length > 160 ? `${body.slice(0, 157)}…` : body,
      icon: icon || "/braxy-logo.png",
      tag,
      silent,
    });
    n.onclick = () => {
      window.focus();
      onClick?.();
      n.close();
    };
  } catch {
    // Mobile Chrome only allows notifications through a service worker.
  }
}

// -- unread badge in the tab title ------------------------------------

const baseTitle = typeof document !== "undefined" ? document.title : "Braxy";
let unseen = 0;

/** Counts activity that arrived while the app was in the background. */
export function bumpTitleBadge(): void {
  unseen += 1;
  document.title = `(${unseen}) ${baseTitle}`;
}

export function clearTitleBadge(): void {
  if (!unseen) return;
  unseen = 0;
  document.title = baseTitle;
}
