import { Outlet } from "react-router-dom";
import { useRealtime } from "../../hooks/useRealtime";
import { useMe } from "../../lib/queries";
import { useUi } from "../../store/ui";
import { Modals } from "../Modals";
import { Toasts } from "../notifications/Toasts";
import { Sidebar } from "../sidebar/Sidebar";
import { Footer } from "./Footer";
import styles from "./Shell.module.css";
import { TopBar } from "./TopBar";

export function Shell() {
  const me = useMe();
  useRealtime(me);
  const sidebarOpen = useUi((s) => s.sidebarOpen);
  const setSidebarOpen = useUi((s) => s.setSidebarOpen);

  return (
    <div className={styles.shell}>
      <TopBar />
      <div className={styles.body}>
        <aside className={`${styles.sidebar} ${sidebarOpen ? styles.sidebarOpen : ""}`}>
          <Sidebar />
        </aside>
        {sidebarOpen && <div className={styles.scrim} onClick={() => setSidebarOpen(false)} />}
        <main className={styles.main}>
          <Outlet />
        </main>
      </div>
      <Footer />
      <Toasts />
      <Modals />
    </div>
  );
}
