import { Monitor, Moon, Settings, Sun } from "@productivity-os/shared-ui/components/sf-symbols"
import { Button } from "@productivity-os/shared-ui/components/ui/button"
import {
  useTheme,
  type Theme,
} from "@productivity-os/shared-ui/components/theme-provider"
import { notesPreferences } from "@/api/notes-preferences"

const appearances: Array<{
  value: Theme
  label: string
  icon: React.ReactNode
}> = [
  { value: "system", label: "System", icon: <Monitor /> },
  { value: "light", label: "Light", icon: <Sun /> },
  { value: "dark", label: "Dark", icon: <Moon /> },
]

export function NotesPreferencesWindow() {
  const { theme, setTheme } = useTheme()
  return (
    <main className="notes-preferences-window">
      <header data-tauri-drag-region>
        <span><Settings aria-hidden="true" /></span>
        <div>
          <h1>Notes Settings</h1>
          <p>Choose how Notes looks in every open window.</p>
        </div>
      </header>
      <section aria-labelledby="notes-appearance-label">
        <strong id="notes-appearance-label">Appearance</strong>
        <div role="group" aria-label="Appearance">
          {appearances.map((appearance) => (
            <Button
              key={appearance.value}
              type="button"
              variant={theme === appearance.value ? "default" : "outline"}
              aria-pressed={theme === appearance.value}
              onClick={() => {
                setTheme(appearance.value)
                void notesPreferences.set(appearance.value)
              }}
            >
              {appearance.icon}
              {appearance.label}
            </Button>
          ))}
        </div>
      </section>
    </main>
  )
}
