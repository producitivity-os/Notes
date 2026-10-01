import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { getCurrentWindow } from "@tauri-apps/api/window"
import type { CanvasCardTier } from "@productivity-os/canvas"
import {
  cardEditorWindows,
  type CardEditorSaveResult,
  type CardEditorSession,
  type CardTierPreview,
} from "@/api/card-editor-windows"
import { createNotesCanvasAssets } from "@/canvas/canvas-assets"
import {
  BlankCardEditorDialog,
  type BlankCardEditorHandle,
} from "@/components/blank-card-editor-dialog"

type PendingSave = {
  resolve(): void
  reject(error: Error): void
}

export function CardEditorWindow({ sessionId }: { sessionId: string }) {
  const [session, setSession] = useState<CardEditorSession | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [saveListenerReady, setSaveListenerReady] = useState(false)
  const editorRef = useRef<BlankCardEditorHandle>(null)
  const pendingSaves = useRef(new Map<string, PendingSave>())
  const assets = useMemo(createNotesCanvasAssets, [])

  useEffect(() => {
    let cancelled = false
    void cardEditorWindows
      .session(sessionId)
      .then((value) => {
        if (!cancelled) setSession(value)
      })
      .catch((error: unknown) => {
        if (!cancelled)
          setLoadError(error instanceof Error ? error.message : String(error))
      })
    return () => {
      cancelled = true
    }
  }, [sessionId])

  useEffect(() => {
    let dispose: (() => void) | undefined
    void getCurrentWindow()
      .listen<CardEditorSaveResult>("notes:card-editor-save-result", (event) => {
        const result = event.payload
        if (result.sessionId !== sessionId) return
        const pending = pendingSaves.current.get(result.requestId)
        if (!pending) return
        pendingSaves.current.delete(result.requestId)
        if (result.succeeded) pending.resolve()
        else pending.reject(new Error(result.error || "Couldn’t save card changes."))
      })
      .then((unlisten) => {
        dispose = unlisten
        setSaveListenerReady(true)
      })
      .catch((error: unknown) =>
        setLoadError(error instanceof Error ? error.message : String(error)),
      )
    return () => {
      dispose?.()
      for (const pending of pendingSaves.current.values())
        pending.reject(new Error("The card editor closed before saving."))
      pendingSaves.current.clear()
    }
  }, [sessionId])

  const close = useCallback(async () => {
    await cardEditorWindows.close(sessionId)
    await getCurrentWindow().destroy()
  }, [sessionId])

  useEffect(() => {
    let dispose: (() => void) | undefined
    void getCurrentWindow()
      .onCloseRequested((event) => {
        event.preventDefault()
        if (editorRef.current) void editorRef.current.requestClose()
        else void close()
      })
      .then((unlisten) => {
        dispose = unlisten
      })
    return () => dispose?.()
  }, [close])

  const save = useCallback(
    (tiers: CanvasCardTier[], previews: CardTierPreview[]) => {
      if (!session) return Promise.reject(new Error("Card editor is not ready."))
      const requestId = crypto.randomUUID()
      return new Promise<void>((resolve, reject) => {
        pendingSaves.current.set(requestId, { resolve, reject })
        void cardEditorWindows
          .requestSave({
            sessionId,
            requestId,
            cardId: session.cardId,
            tiers,
            previews,
          })
          .catch((error: unknown) => {
            pendingSaves.current.delete(requestId)
            reject(error instanceof Error ? error : new Error(String(error)))
          })
      })
    },
    [session, sessionId],
  )

  if (loadError)
    return (
      <main className="card-editor-window-message" role="alert">
        <h1>Couldn’t open this card</h1>
        <p>{loadError}</p>
      </main>
    )

  if (!session || !saveListenerReady)
    return <main className="card-editor-window-message">Opening card…</main>

  return (
    <BlankCardEditorDialog
      ref={editorRef}
      standalone
      initialTiers={session.tiers}
      assets={assets}
      onSave={save}
      onClose={close}
    />
  )
}
