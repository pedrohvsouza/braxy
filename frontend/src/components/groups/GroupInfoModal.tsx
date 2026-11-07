import { faCrown, faMagnifyingGlass } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api, ApiError } from "../../lib/api";
import { keys, useConversation, useMe, useMembers, useSidebar } from "../../lib/queries";
import type { ConversationDetail } from "../../lib/types";
import { useUi } from "../../store/ui";
import { Avatar } from "../common/Avatar";
import { Modal } from "../common/Modal";
import { UserName } from "../common/UserName";
import { SanctionList } from "../moderation/SanctionList";
import { FriendPicker } from "./FriendPicker";
import styles from "./Groups.module.css";

export function GroupInfoModal({ conversationId }: { conversationId: number }) {
  const close = useUi((s) => s.closeModal);
  const me = useMe();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { data: convo, dataUpdatedAt } = useConversation(conversationId);
  const { data: sidebar } = useSidebar();
  const [adding, setAdding] = useState(false);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [errors, setErrors] = useState<string[]>([]);
  const file = useRef<HTMLInputElement>(null);

  // Membership changes (here or from the realtime feed) refetch the detail;
  // the member pages follow it.
  useEffect(() => {
    void qc.invalidateQueries({ queryKey: ["members", conversationId] });
  }, [dataUpdatedAt, conversationId, qc]);

  if (!convo) return null;
  const memberIds = new Set(convo.members.map((m) => m.user.id));
  const candidates = (sidebar?.friends ?? []).filter((f) => !memberIds.has(f.user.id));
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: keys.conversation(conversationId) });
    void qc.invalidateQueries({ queryKey: keys.sidebar });
  };
  const guard = async (fn: () => Promise<unknown>) => {
    setErrors([]);
    try {
      await fn();
      refresh();
    } catch (err) {
      setErrors(err instanceof ApiError ? err.errors : [t("common.error")]);
    }
  };

  const rename = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const name = String(new FormData(e.currentTarget).get("name"));
    void guard(() => api.renameGroup(conversationId, name));
  };

  return (
    <Modal title={t("group.infoTitle")} onClose={close} width={460}>
      <div className={styles.form}>
        <div className={styles.groupTop}>
          <Avatar name={convo.name ?? "Grupo"} url={convo.avatar_url} size={64} group />
          {convo.can_manage ? (
            <form className={styles.renameForm} onSubmit={rename}>
              <input className="input" name="name" defaultValue={convo.name ?? ""} minLength={2} maxLength={40} required />
              <button className="btn btn-sm">{t("group.rename")}</button>
            </form>
          ) : (
            <strong className={styles.groupTitle}>{convo.name}</strong>
          )}
        </div>
        {convo.can_manage && (
          <div className={styles.row}>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => file.current?.click()}>
              {t("group.changeAvatar")}
            </button>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => setAdding((a) => !a)}>
              {t("group.addMembers")}
            </button>
            <input
              ref={file}
              type="file"
              hidden
              accept="image/png,image/jpeg,image/gif,image/webp"
              onChange={(e) => {
                const f = e.target.files?.[0];
                e.target.value = "";
                if (f) void guard(() => api.uploadGroupAvatar(conversationId, f));
              }}
            />
          </div>
        )}
        {adding && (
          <div className={styles.addBox}>
            <FriendPicker
              friends={candidates}
              selected={selected}
              onToggle={(id) =>
                setSelected((s) => {
                  const next = new Set(s);
                  if (next.has(id)) next.delete(id);
                  else next.add(id);
                  return next;
                })
              }
            />
            {candidates.length > 0 && (
              <button
                type="button"
                className="btn btn-sm"
                disabled={!selected.size}
                onClick={() =>
                  void guard(async () => {
                    await api.addMembers(conversationId, [...selected]);
                    setSelected(new Set());
                    setAdding(false);
                  })
                }
              >
                {t("group.addMembers")}
              </button>
            )}
          </div>
        )}
        {errors.length > 0 && (
          <ul className="form-errors">
            {errors.map((x) => (
              <li key={x}>{x}</li>
            ))}
          </ul>
        )}
        <MemberList convo={convo} onRemove={(userId) => void guard(() => api.removeMember(conversationId, userId))} />
        {convo.can_moderate && <SanctionList conversationId={convo.id} />}
        {convo.kind === "group" && !convo.can_manage && (
          <button
            type="button"
            className="btn btn-danger"
            onClick={() => {
              if (!window.confirm(t("group.leaveConfirm"))) return;
              void guard(async () => {
                await api.removeMember(conversationId, me.id);
                close();
                navigate("/");
              });
            }}
          >
            {t("group.leave")}
          </button>
        )}
      </div>
    </Modal>
  );
}

function useDebounced<T>(value: T, ms: number): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = window.setTimeout(() => setV(value), ms);
    return () => window.clearTimeout(id);
  }, [value, ms]);
  return v;
}

/** Paginated, searchable member list; loads more as the end scrolls in. */
function MemberList({ convo, onRemove }: { convo: ConversationDetail; onRemove: (userId: number) => void }) {
  const openModal = useUi((s) => s.openModal);
  const [term, setTerm] = useState("");
  const q = useDebounced(term.trim(), 250);
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage, isLoading } = useMembers(convo.id, q);
  const sentinel = useRef<HTMLDivElement>(null);
  const members = data?.pages.flatMap((p) => p.members) ?? [];

  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasNextPage || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting) && !isFetchingNextPage) void fetchNextPage();
    });
    io.observe(el);
    return () => io.disconnect();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  return (
    <>
      <h3 className={styles.subTitle}>
        {t("group.membersTitle")} · {convo.member_count.toLocaleString("pt-BR")}
      </h3>
      {convo.member_count > 8 && (
        <label className={styles.memberSearch}>
          <FontAwesomeIcon icon={faMagnifyingGlass} aria-hidden />
          <input
            className="input"
            type="search"
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            placeholder={t("group.searchMembers")}
            aria-label={t("group.searchMembers")}
          />
        </label>
      )}
      <div className={styles.members} data-testid="member-list">
        {members.map((m) => (
          <div key={m.user.id} className={styles.member}>
            <button type="button" className={styles.memberMain} onClick={() => openModal({ kind: "profile", username: m.user.username })}>
              <Avatar name={m.user.name} url={m.user.avatar_url} size={34} online={m.online} />
              <UserName name={m.user.name} role={m.user.role} level={m.user.level} />
              {m.role === "owner" && <FontAwesomeIcon icon={faCrown} className={styles.crown} title={t("group.owner")} />}
            </button>
            {convo.can_manage && m.role !== "owner" && (
              <button type="button" className="btn btn-sm btn-ghost" onClick={() => onRemove(m.user.id)}>
                {t("group.remove")}
              </button>
            )}
          </div>
        ))}
        {!isLoading && members.length === 0 && <p className={styles.memberNote}>{t("group.noMembersFound")}</p>}
        {(isLoading || isFetchingNextPage) && <p className={styles.memberNote}>{t("common.loading")}</p>}
        <div ref={sentinel} aria-hidden className={styles.sentinel} />
      </div>
    </>
  );
}
