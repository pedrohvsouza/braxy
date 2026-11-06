import { t } from "../../i18n";
import type { SidebarFriend } from "../../lib/types";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Groups.module.css";

interface Props {
  friends: SidebarFriend[];
  selected: Set<number>;
  onToggle: (id: number) => void;
}

export function FriendPicker({ friends, selected, onToggle }: Props) {
  if (!friends.length) return <p className="muted">{t("group.noFriendsToAdd")}</p>;
  return (
    <div className={styles.picker}>
      {friends.map((f) => (
        <label key={f.user.id} className={styles.pick}>
          <input type="checkbox" checked={selected.has(f.user.id)} onChange={() => onToggle(f.user.id)} data-testid={`pick-${f.user.username}`} />
          <Avatar name={f.user.name} url={f.user.avatar_url} size={32} online={f.online} />
          <UserName name={f.user.name} role={f.user.role} level={f.user.level} />
        </label>
      ))}
    </div>
  );
}
