import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { keys } from "../../lib/queries";
import type { SearchResult } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { UserName } from "../common/UserName";
import styles from "./Sidebar.module.css";

export function FriendAction({ result, onDone }: { result: Pick<SearchResult, "user" | "friendship">; onDone?: () => void }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ["search"] });
    void qc.invalidateQueries({ queryKey: ["profile"] });
    void qc.invalidateQueries({ queryKey: keys.friendships });
    void qc.invalidateQueries({ queryKey: keys.sidebar });
  };
  const { status, id } = result.friendship;

  if (status === "friends") {
    return (
      <button
        className="btn btn-sm"
        type="button"
        onClick={async () => {
          const { conversation } = await api.openDm(result.user.id);
          refresh();
          onDone?.();
          navigate(`/c/${conversation.id}`);
        }}
      >
        {t("friend.message")}
      </button>
    );
  }
  if (status === "incoming" && id) {
    return (
      <button className="btn btn-sm" type="button" onClick={() => api.acceptFriend(id).then(refresh)}>
        {t("friend.accept")}
      </button>
    );
  }
  if (status === "outgoing") {
    return (
      <button className="btn btn-sm btn-ghost" type="button" disabled>
        {t("friend.pending")}
      </button>
    );
  }
  if (status === "none") {
    return (
      <button className="btn btn-sm" type="button" onClick={() => api.requestFriend(result.user.id).then(refresh)}>
        {t("friend.add")}
      </button>
    );
  }
  return null;
}

export function SearchResults({ query, onDone }: { query: string; onDone: () => void }) {
  const openModal = useUi((s) => s.openModal);
  const { data, isLoading } = useQuery({
    queryKey: keys.search(query),
    queryFn: () => api.searchUsers(query).then((r) => r.users),
    enabled: query.length > 0,
  });

  return (
    <div className={styles.section}>
      <h3 className={styles.sectionTitle}>{t("sidebar.results")}</h3>
      {isLoading && <p className={styles.hint}>{t("common.loading")}</p>}
      {data?.length === 0 && <p className={styles.hint}>{t("sidebar.noResults")}</p>}
      {data?.map((r) => (
        <div key={r.user.id} className={styles.row} data-testid={`search-${r.user.username}`}>
          <button className={styles.rowMain} type="button" onClick={() => openModal({ kind: "profile", username: r.user.username })}>
            <Avatar name={r.user.name} url={r.user.avatar_url} size={38} online={r.friendship.status === "friends" ? r.online : null} />
            <span className={styles.rowText}>
              <UserName name={r.user.name} role={r.user.role} level={r.user.level} />
              <span className={styles.preview}>@{r.user.username}</span>
            </span>
          </button>
          <FriendAction result={r} onDone={onDone} />
        </div>
      ))}
    </div>
  );
}
