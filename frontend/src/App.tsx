import { Navigate, Route, Routes } from "react-router-dom";
import { AuthPage } from "./components/auth/AuthPage";
import { ChatView } from "./components/chat/ChatView";
import { EmptyState } from "./components/empty/EmptyState";
import { ServerStarting } from "./components/layout/ServerStarting";
import { Shell } from "./components/layout/Shell";
import { isUnavailable } from "./lib/api";
import { useSession } from "./lib/queries";

export function App() {
  const { data, error, isLoading, isError, isFetching, refetch } = useSession();

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
