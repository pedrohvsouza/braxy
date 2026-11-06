import { faCode, faHeadset, faUser, faUserGear, faUserShield, type IconDefinition } from "@fortawesome/free-solid-svg-icons";
import { t } from "../i18n";
import type { Role } from "./types";

export const ROLE_ICON: Record<Role, IconDefinition> = {
  developer: faCode,
  admin: faUserShield,
  moderator: faUserGear,
  support: faHeadset,
  member: faUser,
};

export const roleLabel = (role: Role) => t(`role.${role}`);

/** Level number color tier (independent from the role color). */
export function levelTier(level: number): string {
  if (level >= 40) return "tier-5";
  if (level >= 30) return "tier-4";
  if (level >= 20) return "tier-3";
  if (level >= 10) return "tier-2";
  return "tier-1";
}
