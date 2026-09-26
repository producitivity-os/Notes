import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@productivity-os/shared-ui/globals.css";
import { SharedUiProvider } from "@productivity-os/shared-ui/components/shared-ui-provider";
import { ThemeProvider } from "@productivity-os/shared-ui/components/theme-provider";
import { Toaster } from "@productivity-os/shared-ui/components/ui/toaster";
import "@/App.css";
import App from "@/App";

const NOTES_THEME_KEY = "notes-theme";
const LEGACY_NOTES_THEME_KEY = "notes-home-theme";
const isNotebookWindow =
  /^\/notebook\/[^/]+/.test(window.location.pathname) ||
  new URLSearchParams(window.location.search).has("notebookId");
if (!window.localStorage.getItem(NOTES_THEME_KEY)) {
  const legacyTheme = window.localStorage.getItem(LEGACY_NOTES_THEME_KEY);
  if (legacyTheme) window.localStorage.setItem(NOTES_THEME_KEY, legacyTheme);
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider defaultTheme="dark" storageKey={NOTES_THEME_KEY}>
      <SharedUiProvider
        applicationBackgroundMenu={isNotebookWindow ? "none" : "reload"}
      >
        <App />
        <Toaster />
      </SharedUiProvider>
    </ThemeProvider>
  </StrictMode>,
);
