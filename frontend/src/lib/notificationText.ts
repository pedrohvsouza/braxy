import { t } from "../i18n";
import type { AppNotification } from "./types";

export function notificationText(n: AppNotification): string {
  const actor = n.actor?.name ?? "Alguém";
  const where = String(n.payload.conversation_name ?? "Grupo");
  const preview = String(n.payload.preview ?? "");
  switch (n.kind) {
    case "level_up":
      return t("notif.level_up", { level: Number(n.payload.level ?? 0) });
    case "mention":
      return t("notif.mention", { actor, where, preview });
    case "reply":
      return t("notif.reply", { actor, where, preview });
    case "group_added":
      return t("notif.group_added", { actor, where });
    case "friend_accepted":
      return t("notif.friend_accepted", { actor });
    case "friend_request":
      return t("notif.friend_request", { actor });
  }
}
