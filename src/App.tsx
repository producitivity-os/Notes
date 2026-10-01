import { useEffect } from "react"
import { Home } from "@/pages/Home"
import { NotebookDetail } from "@/pages/NotebookDetail"
import { NotebookErrorBoundary } from "@/components/notebook-error-boundary"
import { CardEditorWindow } from "@/components/card-editor-window"
import { NotesPreferencesWindow } from "@/components/notes-preferences-window"
import { notesPreferences } from "@/api/notes-preferences"
import {
  useTheme,
  type Theme,
} from "@productivity-os/shared-ui/components/theme-provider"

const NOTES_NATIVE_SYSTEM_THEME_MIGRATION =
  "notes-theme:native-system-theme:2026-09"

function NotesThemeWindowSync() {
  const { theme, setTheme } = useTheme()
  useEffect(() => {
    let cancelled = false
    let unlisten: (() => void) | undefined
    const migrateNativePreference =
      window.localStorage.getItem(NOTES_NATIVE_SYSTEM_THEME_MIGRATION) !==
      "complete"
    if (migrateNativePreference) {
      setTheme("system")
      void notesPreferences
        .set("system")
        .then(() => {
          window.localStorage.setItem(
            NOTES_NATIVE_SYSTEM_THEME_MIGRATION,
            "complete",
          )
        })
        .catch(() => undefined)
    } else {
      void notesPreferences
        .get()
        .then((preferences) => {
          if (cancelled) return
          if (preferences.initialized) setTheme(preferences.appearance)
          else void notesPreferences.set(theme)
        })
        .catch(() => undefined)
    }
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen<Theme>("notes:theme-changed", (event) => setTheme(event.payload)),
      )
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => {
      cancelled = true
      unlisten?.()
    }
  }, [setTheme, theme])
  return null
}

export default function App() {
  const preferencesWindow = new URLSearchParams(window.location.search).has(
    "notesPreferences",
  )
  const cardEditorSession = new URLSearchParams(window.location.search).get(
    "cardEditorSession",
  )
  const match = window.location.pathname.match(/^\/notebook\/([^/]+)/)
  const notebookId = match?.[1]
    ? decodeURIComponent(match[1])
    : new URLSearchParams(window.location.search).get("notebookId")
  return (
    <>
      <NotesThemeWindowSync />
      {preferencesWindow ? (
        <NotesPreferencesWindow />
      ) : cardEditorSession ? (
        <CardEditorWindow sessionId={cardEditorSession} />
      ) : notebookId ? (
        <NotebookErrorBoundary>
          <NotebookDetail notebookId={notebookId} />
        </NotebookErrorBoundary>
      ) : (
        <Home />
      )}
    </>
  )
}
