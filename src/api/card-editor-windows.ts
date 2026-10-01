import { invoke } from "@tauri-apps/api/core"
import type { CanvasCardTier } from "@productivity-os/canvas"

export type CardTierPreview = {
  tierId: string
  tierRevision: number
  dataUrl: string
}

export type CardEditorSession = {
  sessionId: string
  notebookId: string
  notebookTitle: string
  cardId: string
  tiers: CanvasCardTier[]
}

export type CardEditorSaveRequest = {
  sessionId: string
  requestId: string
  cardId: string
  tiers: CanvasCardTier[]
  previews: CardTierPreview[]
}

export type CardEditorSaveResult = {
  sessionId: string
  requestId: string
  succeeded: boolean
  error?: string | null
}

export type CardEditorLifecycle = {
  sessionId: string
  notebookId: string
  open: boolean
}

export const cardEditorWindows = {
  open(input: {
    notebookId: string
    notebookTitle: string
    cardId: string
    tiers: CanvasCardTier[]
  }) {
    return invoke<string>("open_card_editor_window", { input })
  },

  session(sessionId: string) {
    return invoke<CardEditorSession>("card_editor_session", { sessionId })
  },

  requestSave(input: CardEditorSaveRequest) {
    return invoke<void>("request_card_editor_save", { input })
  },

  resolveSave(input: CardEditorSaveResult) {
    return invoke<void>("resolve_card_editor_save", { input })
  },

  close(sessionId: string) {
    return invoke<void>("close_card_editor_session", { sessionId })
  },
}
