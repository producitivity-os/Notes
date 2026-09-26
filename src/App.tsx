import { useEffect } from "react";
import { Home } from "@/pages/Home";
import { NotebookDetail } from "@/pages/NotebookDetail";
import { NotebookErrorBoundary } from "@/components/notebook-error-boundary";
import {
  useTheme,
  type Theme,
} from "@productivity-os/shared-ui/components/theme-provider";

function NotesThemeWindowSync() {
  const { setTheme } = useTheme();
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen<Theme>("notes:theme-changed", (event) =>
          setTheme(event.payload),
        ),
      )
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => unlisten?.();
  }, [setTheme]);
  return null;
}

export default function App() {
  const match = window.location.pathname.match(/^\/notebook\/([^/]+)/);
  const notebookId = match?.[1]
    ? decodeURIComponent(match[1])
    : new URLSearchParams(window.location.search).get("notebookId");
  return (
    <>
      <NotesThemeWindowSync />
      {notebookId ? (
        <NotebookErrorBoundary>
          <NotebookDetail notebookId={notebookId} />
        </NotebookErrorBoundary>
      ) : (
        <Home />
      )}
    </>
  );
}
