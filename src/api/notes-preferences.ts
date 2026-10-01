import { invoke } from "@tauri-apps/api/core"
import type { Theme } from "@productivity-os/shared-ui/components/theme-provider"

export type NotesPreferences = {
  appearance: Theme
  initialized: boolean
}

export const notesPreferences = {
  get() {
    return invoke<NotesPreferences>("get_notes_preferences")
  },
  set(appearance: Theme) {
    return invoke<void>("set_notes_preferences", { appearance })
  },
}
