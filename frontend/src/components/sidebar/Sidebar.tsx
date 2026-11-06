import { faUserGroup, faUsers } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { shortTime } from "../../lib/format";
import { keys, useFriendships, useSidebar } from "../../lib/queries";
import { roleLabel } from "../../lib/roles";
import type { SidebarFriend, SidebarGroup } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import { ProfileHeader } from "./ProfileHeader";
import { SearchResults } from "./SearchResults";
import styles from "./Sidebar.module.css";

function useDebounced(value: string, ms = 250) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = window.setTimeout(() => setV(value), ms);
    return () => window.clearTimeout(id);
  }, [value, ms]);
  return v;
}

function GroupRow({ g, active }: { g: SidebarGroup; active: boolean }) {
  const navigate = useNavigate();
  const setSidebarOpen = useUi((s) => s.setSidebarOpen);
  const typing = useUi((s) => s.typing[g.conversation_id]);
  const typers = typing ? Object.values(typing).map((x) => x.name) : [];
  return (
    <button
      type="button"
      className={`${styles.row} ${styles.rowMain} ${active ? styles.active : ""}`}
      onClick={() => {
        setSidebarOpen(false);
        navigate(`/c/${g.conversation_id}`);
      }}
      data-testid={`group-${g.conversation_id}`}
    >
      {g.avatar_url ? (
        <Avatar name={g.name} url={g.avatar_url} size={40} />
      ) : (
        <span className={styles.groupIcon}>
          <FontAwesomeIcon icon={g.kind === "lobby" ? faUsers : faUserGroup} />
        </span>
      )}
      <span className={styles.rowText}>
        <span className={styles.rowTop}>
          <span className={`${styles.groupName} ${g.kind === "lobby" ? styles.lobbyName : ""}`}>{g.name}</span>
          <span className={styles.time}>{shortTime(g.last_message?.created_at)}</span>
        </span>
        <span className={styles.rowBottom}>
          <span className={`${styles.preview} ${typers.length ? styles.typing : ""}`}>
            {typers.length
              ? t("chat.typingOne", { name: typers[0] })
              : g.last_message
                ? `${g.last_message.author_name}: ${g.last_message.preview}`
                : t("sidebar.noMessages")}
          </span>
          {g.unread > 0 && <span className="badge">{g.unread > 99 ? "99+" : g.unread}</span>}
        </span>
      </span>
    </button>
  );
}

function FriendRow({ f, active }: { f: SidebarFriend; active: boolean }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const setSidebarOpen = useUi((s) => s.setSidebarOpen);
  const typing = useUi((s) => (f.conversation_id ? s.typing[f.conversation_id] : undefined));
  const open = async () => {
    setSidebarOpen(false);
    if (f.conversation_id) {
      navigate(`/c/${f.conversation_id}`);
      return;
    }
    const { conversation } = await api.openDm(f.user.id);
    void qc.invalidateQueries({ queryKey: keys.sidebar });
    navigate(`/c/${conversation.id}`);
  };
  return (
    <button type="button" className={`${styles.row} ${styles.rowMain} ${active ? styles.active : ""}`} onClick={open} data-testid={`friend-${f.user.username}`}>
      <Avatar name={f.user.name} url={f.user.avatar_url} size={40} online={f.online} />
      <span className={styles.rowText}>
        <span className={styles.rowTop}>
          <UserName name={f.user.name} role={f.user.role} level={f.user.level} />
          <span className={styles.time}>{shortTime(f.last_message?.created_at)}</span>
        </span>
        <span className={styles.rowBottom}>
          <span className={`${styles.preview} ${typing ? styles.typing : ""}`}>
            {typing
              ? t("chat.typingOne", { name: f.user.name })
              : f.last_message
                ? `${f.last_message.author_name === "Você" ? "Você: " : ""}${f.last_message.preview}`
                : roleLabel(f.user.role) + " · " + t("sidebar.startChat")}
          </span>
          {f.unread > 0 && <span className="badge">{f.unread > 99 ? "99+" : f.unread}</span>}
        </span>
      </span>
    </button>
  );
}

export function Sidebar() {
  const { id } = useParams();
  const activeId = id ? Number(id) : null;
  const { data } = useSidebar();
  const { data: requests } = useFriendships();
  const openModal = useUi((s) => s.openModal);
  const searchFocus = useUi((s) => s.searchFocus);
  const [query, setQuery] = useState("");
  const debounced = useDebounced(query.trim());
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (searchFocus) inputRef.current?.focus();
  }, [searchFocus]);

  const incoming = requests?.incoming.length ?? 0;

  return (
    <div className={styles.sidebar}>
      <ProfileHeader />
      <div className={styles.searchBox}>
        <input
          ref={inputRef}
          className="input"
          placeholder={t("sidebar.search")}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === "Escape" && setQuery("")}
          aria-label={t("sidebar.search")}
        />
      </div>
      <div className={styles.lists}>
        {debounced ? (
          <SearchResults query={debounced} onDone={() => setQuery("")} />
        ) : (
          <>
            {incoming > 0 && (
              <button type="button" className={styles.requests} onClick={() => openModal({ kind: "requests" })}>
                {t("sidebar.requests")} <span className="badge">{incoming}</span>
              </button>
            )}
            <div className={styles.section}>
              <h3 className={styles.sectionTitle}>{t("sidebar.groups")}</h3>
              {data?.groups.map((g) => <GroupRow key={g.conversation_id} g={g} active={g.conversation_id === activeId} />)}
            </div>
            <div className={styles.section}>
              <h3 className={styles.sectionTitle}>{t("sidebar.friends")}</h3>
              {data && data.friends.length === 0 && <p className={styles.hint}>{t("sidebar.noFriends")}</p>}
              {data?.friends.map((f) => (
                <FriendRow key={f.user.id} f={f} active={f.conversation_id !== null && f.conversation_id === activeId} />
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
