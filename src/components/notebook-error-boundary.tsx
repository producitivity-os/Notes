import * as React from "react";
import { AlertTriangle, RefreshCw, X } from "@productivity-os/shared-ui/components/sf-symbols";

import { Button } from "@productivity-os/shared-ui/components/ui/button";

type NotebookErrorBoundaryProps = React.PropsWithChildren;
type NotebookErrorBoundaryState = { error: Error | null };

class NotebookErrorBoundary extends React.Component<
  NotebookErrorBoundaryProps,
  NotebookErrorBoundaryState
> {
  state: NotebookErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: unknown): NotebookErrorBoundaryState {
    return {
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error("Notebook detail failed to render", error, info);
  }

  private closeWindow = () => {
    const isTauri = "__TAURI_INTERNALS__" in window || "__TAURI__" in window;
    if (!isTauri) {
      window.close();
      return;
    }
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) => getCurrentWindow().close())
      .catch(() => window.close());
  };

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <main className="notebook-render-error" role="alert">
        <div className="notebook-render-error-card">
          <span className="notebook-render-error-icon" aria-hidden="true">
            <AlertTriangle />
          </span>
          <h1>Couldn’t open this notebook</h1>
          <p>{this.state.error.message}</p>
          <div className="notebook-render-error-actions">
            <Button type="button" onClick={() => window.location.reload()}>
              <RefreshCw /> Retry
            </Button>
            <Button type="button" variant="outline" onClick={this.closeWindow}>
              <X /> Close
            </Button>
          </div>
        </div>
      </main>
    );
  }
}

export { NotebookErrorBoundary };
