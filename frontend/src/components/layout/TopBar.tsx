import {
  faBars, faBell, faCaretDown, faGear, faHouse, faMagnifyingGlass, faPlus, faRightFromBracket,
  faUser, faUserPlus, faUsers,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { t } from "../../i18n";
import { api } from "../../lib/api";
import { keys, useMe, useNotifications } from "../../lib/queries";
import { useUi } from "../../store/ui";
import { Dropdown, MenuItem } from "../common/Dropdown";
import { NotificationList } from "../notifications/NotificationList";
import styles from "./Shell.module.css";

export function TopBar() {
  const me = useMe();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const openModal = useUi((s) => s.openModal);
  const focusSearch = useUi((s) => s.focusSearch);
  const setSidebarOpen = useUi((s) => s.setSidebarOpen);
  const { data: notifications } = useNotifications();
  const unread = notifications?.unread_count ?? 0;

  const logout = async () => {
    await api.logout().catch(() => undefined);
    navigate("/");
    // Flip the session first (App unmounts the shell), then drop the rest.
    qc.setQueryData(keys.session, { user: null });
    qc.removeQueries({ predicate: (q) => q.queryKey[0] !== keys.session[0] });
  };

  return (
    <header className={styles.topbar}>
      <button className={`icon-btn ${styles.burger}`} onClick={() => setSidebarOpen(true)} aria-label={t("top.menu")} type="button">
        <FontAwesomeIcon icon={faBars} />
      </button>
      <button className={styles.logo} onClick={() => navigate("/")} type="button" aria-label={t("top.home")}>
        <img src="/braxy-logo.png" alt="" />
        <span>BRAXY</span>
      </button>

      <nav className={styles.actions} aria-label="Ações">
        <button className={`icon-btn ${styles.homeBtn}`} onClick={() => navigate("/")} aria-label={t("top.home")} title={t("top.home")} type="button">
          <FontAwesomeIcon icon={faHouse} />
        </button>

        <Dropdown label={t("top.profile")} trigger={() => (<><FontAwesomeIcon icon={faUser} /><FontAwesomeIcon icon={faCaretDown} className={styles.caret} /></>)}>
          {(close) => (
            <>
              <MenuItem icon={<FontAwesomeIcon icon={faUser} />} onClick={() => { close(); openModal({ kind: "profile", username: me.username }); }}>
                {t("top.profile")}
              </MenuItem>
              <MenuItem icon={<FontAwesomeIcon icon={faRightFromBracket} />} onClick={() => { close(); void logout(); }} danger>
                {t("top.logout")}
              </MenuItem>
            </>
          )}
        </Dropdown>

        <button className="icon-btn" onClick={() => openModal({ kind: "settings" })} aria-label={t("top.settings")} title={t("top.settings")} type="button">
          <FontAwesomeIcon icon={faGear} />
        </button>

        <Dropdown label={t("top.create")} trigger={() => (<><FontAwesomeIcon icon={faPlus} /><FontAwesomeIcon icon={faCaretDown} className={styles.caret} /></>)}>
          {(close) => (
            <>
              <MenuItem icon={<FontAwesomeIcon icon={faUsers} />} onClick={() => { close(); openModal({ kind: "createGroup" }); }}>
                {t("top.newGroup")}
              </MenuItem>
              <MenuItem icon={<FontAwesomeIcon icon={faUserPlus} />} onClick={() => { close(); focusSearch(); }}>
                {t("top.addFriend")}
              </MenuItem>
            </>
          )}
        </Dropdown>

        <button className="icon-btn" onClick={focusSearch} aria-label={t("top.search")} title={t("top.search")} type="button">
          <FontAwesomeIcon icon={faMagnifyingGlass} />
        </button>

        <Dropdown
          label={t("top.notifications")}
          trigger={() => (
            <>
              <FontAwesomeIcon icon={faBell} className={unread ? styles.bellActive : undefined} />
              {unread > 0 && <span className={`badge ${styles.bellBadge}`} data-testid="bell-count">{unread > 99 ? "99+" : unread}</span>}
            </>
          )}
        >
          {(close) => <NotificationList onNavigate={close} />}
        </Dropdown>
      </nav>
    </header>
  );
}
