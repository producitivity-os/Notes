import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import {
  CanvasSurfaceContextMenu,
  CanvasToolbar,
  EndlessCanvas,
  type CanvasCardObject,
  type CanvasCardTier,
  type CanvasTool,
  type EndlessCanvasHandle,
  type EndlessCanvasOptions,
  type EndlessCanvasState,
  type PluginCard,
} from "@productivity-os/canvas"
import { BlankCardEditorDialog } from "@/components/blank-card-editor-dialog"
import { CardEditorDialog } from "@/components/card-editor-dialog"
import type { NotebookSummary, PersonRecord } from "@/api/notebook-data"
import type {
  CardPluginDefinition,
  CardPluginHostServices,
} from "@/plugins/plugin-api"
import {
  postNative,
  requestNativeAsset,
  requestNative,
  subscribeNativeBridge,
  uploadNativeImage,
  type NativePage,
} from "./bridge"
import "./native-canvas.css"
import {
  nativeMediaURL,
  nativePluginCards,
  nativePluginDefinition,
} from "./native-plugins"

const enabledTools: readonly CanvasTool[] = [
  "select",
  "hand",
  "text",
  "markdown",
  "card",
  "markdown-card",
  "rect",
  "ellipse",
  "diamond",
  "pentagon",
  "parallelogram",
  "arrow",
  "line",
  "pencil",
  "image",
  "video",
]

type NativeCardEditor =
  | { kind: "blank"; cardID: string; tiers: CanvasCardTier[] }
  | {
      kind: "plugin"
      cardID: string
      plugin: CardPluginDefinition<any, any>
      initialData: Record<string, unknown>
    }

export function NativeCanvasApp() {
  const canvasRef = useRef<EndlessCanvasHandle>(null)
  const stateRef = useRef<EndlessCanvasState | null>(null)
  const revisionRef = useRef(0)
  const saveTimer = useRef<number | null>(null)
  const previewTimer = useRef<number | null>(null)
  const saveInFlight = useRef(false)
  const savePending = useRef(false)
  const dirty = useRef(false)
  const saveIdleWaiters = useRef<Array<() => void>>([])
  const pendingFocusObjectID = useRef<string | null>(null)
  const [page, setPage] = useState<NativePage | null>(null)
  const [tool, setTool] = useState<CanvasTool>("select")
  const [cardEditor, setCardEditor] = useState<NativeCardEditor | null>(null)
  const peopleRef = useRef(new Map<string, PersonRecord>())

  const resolveSaveIdle = useCallback(() => {
    if (saveInFlight.current || savePending.current || dirty.current) return
    const waiters = saveIdleWaiters.current.splice(0)
    waiters.forEach((resolve) => resolve())
  }, [])

  const sendLatestChange = useCallback(() => {
    if (!page || !stateRef.current) return
    if (saveInFlight.current) {
      if (dirty.current) savePending.current = true
      return
    }
    if (!dirty.current) {
      savePending.current = false
      resolveSaveIdle()
      return
    }
    saveInFlight.current = true
    savePending.current = false
    dirty.current = false
    postNative("pageChanged", {
      pageID: page.pageID,
      revision: revisionRef.current,
      canvas: stateRef.current,
    })
  }, [page, resolveSaveIdle])

  const emitChange = useCallback((force = false) => {
    if (saveTimer.current !== null) window.clearTimeout(saveTimer.current)
    saveTimer.current = null
    if (force) sendLatestChange()
    else saveTimer.current = window.setTimeout(() => {
      saveTimer.current = null
      sendLatestChange()
    }, 450)
  }, [sendLatestChange])

  const waitForSaveIdle = useCallback(() => {
    if (!saveInFlight.current && !savePending.current && !dirty.current) return Promise.resolve()
    return new Promise<void>((resolve) => saveIdleWaiters.current.push(resolve))
  }, [])

  const generatePreview = useCallback(async () => {
    if (!page || !canvasRef.current) return
    try {
      const dataURL = await canvasRef.current.captureSnapshot({ format: "png", resolution: 0.45 })
      postNative("previewGenerated", { pageID: page.pageID, dataURL })
    } catch (error) {
      postNative("error", { message: `Could not refresh the page preview: ${String(error)}` })
    }
  }, [page])

  const schedulePreview = useCallback(() => {
    if (previewTimer.current !== null) window.clearTimeout(previewTimer.current)
    previewTimer.current = window.setTimeout(() => {
      previewTimer.current = null
      void generatePreview()
    }, 1_200)
  }, [generatePreview])

  useEffect(() => subscribeNativeBridge((message) => {
    switch (message.type) {
      case "loadPage": {
        const incoming = message.body as unknown as NativePage
        saveInFlight.current = false
        savePending.current = false
        dirty.current = false
        stateRef.current = structuredClone(incoming.canvas)
        revisionRef.current = incoming.revision
        setPage(incoming)
        break
      }
      case "pageSaved":
        if (message.body.pageID === page?.pageID && typeof message.body.revision === "number") {
          revisionRef.current = message.body.revision
          saveInFlight.current = false
          if (savePending.current || dirty.current) sendLatestChange()
          else resolveSaveIdle()
        }
        break
      case "staleRevision":
        if (page && message.body.pageID === page.pageID && typeof message.body.revision === "number") {
          revisionRef.current = message.body.revision
          saveInFlight.current = false
          savePending.current = false
          dirty.current = false
          if (message.body.canvas) {
            const next: NativePage = { ...page, revision: message.body.revision, canvas: message.body.canvas as EndlessCanvasState }
            stateRef.current = structuredClone(next.canvas)
            setPage(next)
          }
          resolveSaveIdle()
        }
        break
      case "flushPage": {
        if (saveTimer.current !== null) window.clearTimeout(saveTimer.current)
        saveTimer.current = null
        emitChange(true)
        void waitForSaveIdle()
          .then(generatePreview)
          .finally(() => postNative("flushComplete", { pageID: page?.pageID }))
        break
      }
      case "focusObject": {
        const objectID = message.body.objectID
        if (typeof objectID === "string" && !canvasRef.current?.focusObject(objectID)) {
          pendingFocusObjectID.current = objectID
        }
        break
      }
    }
  }), [emitChange, generatePreview, page, resolveSaveIdle, sendLatestChange, waitForSaveIdle])

  useEffect(() => {
    const objectID = pendingFocusObjectID.current
    if (!page || !objectID) return
    const frame = window.requestAnimationFrame(() => {
      if (canvasRef.current?.focusObject(objectID)) pendingFocusObjectID.current = null
    })
    return () => window.cancelAnimationFrame(frame)
  }, [page])

  useEffect(() => {
    postNative("ready")
    const onBeforeUnload = () => emitChange(true)
    window.addEventListener("beforeunload", onBeforeUnload)
    return () => {
      window.removeEventListener("beforeunload", onBeforeUnload)
      if (saveTimer.current !== null) window.clearTimeout(saveTimer.current)
      if (previewTimer.current !== null) window.clearTimeout(previewTimer.current)
    }
  }, [emitChange])

  const canvasAssets = useMemo<NonNullable<EndlessCanvasOptions["assets"]>>(() => ({
    pickImage: async () => {
      const asset = await requestNativeAsset("image")
      return asset ? {
        dataUrl: asset.url,
        name: asset.filename,
        width: asset.width,
        height: asset.height,
      } : null
    },
    pickVideo: async () => {
      const asset = await requestNativeAsset("video")
      return asset ? {
        src: asset.url,
        mediaId: asset.hash,
        name: asset.filename,
        width: asset.width,
        height: asset.height,
      } : null
    },
    uploadImage: async (dataURL, name) => {
      const asset = await uploadNativeImage(dataURL, name)
      if (!asset) throw new Error("The image import was cancelled.")
      return { url: asset.url, name: asset.filename }
    },
  }), [])

  const pluginServices = useMemo<CardPluginHostServices>(() => ({
    mediaUrl: nativeMediaURL,
    importImage: async (input) => {
      const asset = await uploadNativeImage(input.dataUrl, input.name)
      if (!asset) throw new Error("The image import was cancelled.")
      return {
        id: asset.url,
        name: asset.filename,
        mimeType: asset.mediaType,
        width: asset.width,
        height: asset.height,
        url: asset.url,
      }
    },
    listPersons: async (query) => {
      const people = await requestNative<PersonRecord[]>("listPluginPeople", { query: query ?? "" })
      peopleRef.current = new Map(people.map((person) => [person.id, person]))
      return people
    },
    savePerson: async (input) => {
      const person = await requestNative<PersonRecord>("savePluginPerson", { person: input })
      peopleRef.current.set(person.id, person)
      return person
    },
    resolvePersonName: (id, fallback = "") =>
      (id && peopleRef.current.get(id)?.name) || fallback,
    listNotebooks: () => requestNative<NotebookSummary[]>("listPluginNotebooks"),
  }), [])

  const options = useMemo<EndlessCanvasOptions>(() => ({
    viewportMode: "bounded",
    maxPaneDepth: 0,
    shouldEnterCardPane: () => false,
    preserveCardDimensions: true,
    pluginCards: nativePluginCards,
    gridStyle: "lines",
    assets: canvasAssets,
    onObjectActivate: (object) => {
      if (object.type !== "card") return
      const card = object as CanvasCardObject
      if (card.kind === "canvas") {
        setCardEditor({
          kind: "blank",
          cardID: card.id,
          tiers: structuredClone(card.tiers),
        })
        return
      }
      if (card.kind !== "plugin") return
      const pluginCard = card as PluginCard
      const plugin = nativePluginDefinition(pluginCard.pluginId)
      if (pluginCard.pluginId === "notes.notebook-card") {
        const notebookID = String(pluginCard.pluginData.targetNotebookId ?? "")
        if (notebookID) postNative("openLinkedNotebook", { notebookID })
        return
      }
      if (plugin?.slots.Editor) {
        setCardEditor({
          kind: "plugin",
          cardID: pluginCard.id,
          plugin,
          initialData: pluginCard.pluginData,
        })
      }
    },
    onError: (error) => postNative("error", { message: String(error) }),
  }), [canvasAssets])

  if (!page) {
    return <div className="native-canvas-loading" aria-label="Loading page" />
  }

  return (
    <main className="native-canvas-shell">
      <CanvasSurfaceContextMenu canvasRef={canvasRef} onError={(error) => postNative("error", { message: String(error) })}>
        <div className="native-page-viewport">
          <PageFit width={page.width} height={page.height}>
            <EndlessCanvas
              key={`${page.pageID}-${page.revision}`}
              ref={canvasRef}
              className="native-page-canvas"
              tool={tool}
              initialState={page.canvas}
              options={options}
              onChange={(state) => {
                stateRef.current = state
                dirty.current = true
                emitChange()
                schedulePreview()
              }}
              onToolChangeRequest={setTool}
            />
          </PageFit>
        </div>
      </CanvasSurfaceContextMenu>
      <CanvasToolbar tool={tool} onToolChange={setTool} enabledTools={enabledTools} />
      {cardEditor?.kind === "blank" && (
        <BlankCardEditorDialog
          key={cardEditor.cardID}
          initialTiers={cardEditor.tiers}
          assets={canvasAssets}
          onSave={(tiers, previews) => {
            const front = tiers[0]
            canvasRef.current?.updateObject(cardEditor.cardID, {
              width: front?.width,
              height: front?.height,
              tiers,
            } as Partial<CanvasCardObject>)
            if (page && previews.length > 0) {
              postNative("cardTierPreviewsGenerated", {
                pageID: page.pageID,
                cardID: cardEditor.cardID,
                previews,
              })
            }
          }}
          onClose={() => setCardEditor(null)}
        />
      )}
      {cardEditor?.kind === "plugin" && (
        <CardEditorDialog
          key={`${cardEditor.plugin.manifest.id}-${cardEditor.cardID}`}
          plugin={cardEditor.plugin}
          mode="edit"
          initialData={cardEditor.initialData}
          services={pluginServices}
          onSave={(pluginData) => {
            canvasRef.current?.updateObject(cardEditor.cardID, {
              pluginData,
              pluginVersion: cardEditor.plugin.manifest.card.schemaVersion,
            } as Partial<PluginCard>)
            setCardEditor(null)
          }}
          onCancel={() => setCardEditor(null)}
        />
      )}
    </main>
  )
}

function PageFit({ width, height, children }: { width: number; height: number; children: React.ReactNode }) {
  const hostRef = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(1)

  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    const observer = new ResizeObserver(([entry]) => {
      const bounds = entry.contentRect
      setScale(Math.min((bounds.width - 56) / width, (bounds.height - 56) / height, 1.4))
    })
    observer.observe(host)
    return () => observer.disconnect()
  }, [height, width])

  return (
    <div ref={hostRef} className="native-page-fit">
      <div className="native-page-paper" style={{ width, height, transform: `scale(${Math.max(scale, 0.1)})` }}>
        {children}
      </div>
    </div>
  )
}
