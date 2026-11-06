import { Navigate, Route, Routes } from "react-router-dom";
import { AuthPage } from "./components/auth/AuthPage";
import { ChatView } from "./components/chat/ChatView";
import { EmptyState } from "./components/empty/EmptyState";
import { Shell } from "./components/layout/Shell";
import { useSession } from "./lib/queries";

export function App() {
  const { data, isLoading, isError, refetch } = useSession();

  if (isLoading) {
    return (
      <div className="boot">
        <img src="/braxy-logo.png" alt="" />
      </div>
    );
  }
  if (isError) {
    return (
      <div className="boot">
        <p>
          Servidor indisponível.{" "}
          <button className="btn btn-sm" onClick={() => void refetch()} type="button">
            Tentar de novo
          </button>
        </p>
      </div>
    );
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
