import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { levelTier, ROLE_ICON, roleLabel } from "../../lib/roles";
import type { Role } from "../../lib/types";
import styles from "./common.module.css";

interface Props {
  name: string;
  role: Role;
  level?: number;
  /** Small role label next to the name ("cargo pequenininho"). */
  showRole?: boolean;
  onClick?: () => void;
  className?: string;
}

export function UserName({ name, role, level, showRole = true, onClick, className = "" }: Props) {
  const Tag = onClick ? "button" : "span";
  return (
    <span className={`${styles.userName} ${className}`}>
      <Tag className={`${styles.nameText} role-name role-${role}`} onClick={onClick} type={onClick ? "button" : undefined}>
        {name}
      </Tag>
      <FontAwesomeIcon icon={ROLE_ICON[role]} className={`role-icon-${role} ${styles.roleIcon}`} title={roleLabel(role)} />
      {showRole && <span className={styles.roleLabel}>{roleLabel(role)}</span>}
      {level !== undefined && <span className={`level ${levelTier(level)} ${styles.level}`}>{level}</span>}
    </span>
  );
}
