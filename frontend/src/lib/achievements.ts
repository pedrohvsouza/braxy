import { t } from "../i18n";
import type { MessageKey } from "../i18n/pt-BR";

// Same keys and order as the backend's Achievements::ALL.
export const ACHIEVEMENTS: { key: string; icon: string }[] = [
  { key: "first_message", icon: "💬" },
  { key: "chatter", icon: "🗣️" },
  { key: "voice_of_the_lobby", icon: "📣" },
  { key: "first_friend", icon: "🤝" },
  { key: "popular", icon: "🌟" },
  { key: "founder", icon: "🏰" },
  { key: "loved", icon: "💖" },
  { key: "regular", icon: "📅" },
  { key: "level_10", icon: "🥉" },
  { key: "level_25", icon: "🥈" },
  { key: "level_50", icon: "🥇" },
];

export function achievementName(key: string): string {
  return t(`achievement.${key}.name` as MessageKey);
}

export function achievementDescription(key: string): string {
  return t(`achievement.${key}.desc` as MessageKey);
}

export function achievementIcon(key: string): string {
  return ACHIEVEMENTS.find((a) => a.key === key)?.icon ?? "🏆";
}
