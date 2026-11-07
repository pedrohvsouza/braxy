import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { AuthPage } from "./components/auth/AuthPage";
import { ResetPasswordPage } from "./components/auth/ResetPasswordPage";
import { ChatView } from "./components/chat/ChatView";
import { EmptyState } from "./components/empty/EmptyState";
import { ServerStarting } from "./components/layout/ServerStarting";
import { Shell } from "./components/layout/Shell";
import { isUnavailable } from "./lib/api";
import { useSession } from "./lib/queries";

export function App() {
  const { data, error, isLoading, isError, isFetching, refetch } = useSession();
  const { pathname } = useLocation();

  if (isLoading) {
    return (
      <div className="boot">
        <img src="/braxy-logo.png" alt="" />
      </div>
    );
  }
  if (isError && !data) {
    return <ServerStarting starting={isUnavailable(error)} retrying={isFetching} onRetry={() => void refetch()} />;
  }
  // The emailed link works signed in or out (it signs in when done).
  if (pathname === "/reset-password") return <ResetPasswordPage />;
  if (!data?.user) return <AuthPage />;

  return (
    <Routes>
      <Route element={<Shell />}>
        <Route index element={<EmptyState />} />
        <Route path="c/:id" element={<ChatView />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
