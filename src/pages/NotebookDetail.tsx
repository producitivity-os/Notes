import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, RefreshCw, Square, X } from "@productivity-os/shared-ui/components/sf-symbols"
import { IconGlyph } from "@productivity-os/shared-ui/components/icon-select"
import { WorkspaceDocumentHeader } from "@productivity-os/shared-ui/components/app-header"
import { Button } from "@productivity-os/shared-ui/components/ui/button"
import { Progress } from "@productivity-os/shared-ui/components/ui/progress"
import { toast } from "@productivity-os/shared-ui/hooks/use-toast"
import {
  EndlessCanvas,
  CanvasMinimap,
  CanvasSurfaceContextMenu,
  CanvasToolbar,
  ImageObject,
  IllustrationCard,
  MarkdownCard,
  canvasObjectFactory,
  groupForShortcut,
  groupForTool,
  minCardHeight,
  minCardWidth,
  nextCustomMenuItem,
  nextToolForGroup,
  type CanvasCardObject,
  type CanvasCardTier,
  type CanvasDrawnPlacement,
  type CanvasObject,
  type CanvasObjectExtension,
  type CanvasObjectOverlaySlotProps,
  type CanvasPaneContext,
  type CanvasPoint,
  type CanvasTool,
  type CanvasToolGroupId,
  type EndlessCanvasHandle,
  type EndlessCanvasOptions,
  type EndlessCanvasState,
  type PluginCard,
} from "@productivity-os/canvas"
import {
  canvasToSnapshot,
  createEmptyNotebookState,
  isTauri,
  notebookData,
  personData,
  pluginData,
  snapshotToCanvas,
  type NotebookDocument,
  type NotebookSummary,
} from "@/api/notebook-data"
import { NotebookPanel } from "@/components/notebook-panel"
import { DiscreteProperties } from "@/components/discrete-properties"
import { BlankCardEditorDialog } from "@/components/blank-card-editor-dialog"
import { CardTierPreviewRegenerator } from "@/components/card-tier-preview-regenerator"
import { MarkdownToolIcon } from "@/components/markdown-tool-icon"
import { CardEditorDialog } from "@/components/card-editor-dialog"
import type { CardPluginDefinition } from "@/plugins/plugin-api"
import type { CardPluginImageInput } from "@/plugins/plugin-api"
import { notesPlugins } from "@/plugins/plugin-registry"
import {
  applyNotebookRootArrowStyle,
  allowsNotebookInsertion,
  migrateNotebookRootArrows,
  migrateLegacyNotebookTextStyles,
  toolsForNotebookDepth,
} from "@/canvas/notebook-policy"
import { migrateLegacyQuestionCards } from "@/canvas/card-tier-migration"
import { createNotesCanvasAssets } from "@/canvas/canvas-assets"
import {
  importNotebookImage,
  notebookMediaData,
  notebookMediaUrl,
} from "@/api/notebook-media"
import { createTauriCanvasClipboard } from "@/api/tauri-canvas-clipboard"
import {
  cardEditorWindows,
  type CardEditorLifecycle,
  type CardEditorSaveRequest,
  type CardTierPreview,
} from "@/api/card-editor-windows"

type NotebookLoadState = {
  progress: number
  label: string
  error: string | null
  visible: boolean
}

type CardEditorState =
  | {
      kind: "blank"
      cardId: string
      tiers: CanvasCardTier[]
    }
  | {
      kind: "plugin"
      mode: "create" | "edit"
      plugin: CardPluginDefinition<any, any>
      point?: CanvasPoint
      cardId?: string
      initialData: unknown
    }

type TierPreviewTask = {
  key: string
  card: CanvasCardObject
}

type InlinePluginEditorState = {
  cardId: string
  regionId: string
}

function PluginInlineEditorOverlay({
  overlay,
  plugin,
  regionId,
  onRegionChange,
  onClose,
}: {
  overlay: CanvasObjectOverlaySlotProps
  plugin: CardPluginDefinition<any, any>
  regionId: string
  onRegionChange(regionId: string): void
  onClose(): void
}) {
  const transactionActive = useRef(false)
  const latestOverlay = useRef(overlay)
  latestOverlay.current = overlay
  const card = overlay.object as PluginCard
  const adapter = plugin.slots.InlineEditor

  useEffect(() => {
    latestOverlay.current.beginMutation()
    transactionActive.current = true
    return () => {
      if (transactionActive.current) latestOverlay.current.commitMutation()
      transactionActive.current = false
    }
  }, [card.id])

  if (!adapter) return null
  const Editor = adapter.Component
  return (
    <Editor
      card={card}
      data={plugin.hydrate(card.pluginData)}
      regionId={regionId}
      scale={overlay.viewport.scale}
      onChange={(data) =>
        overlay.update({
          pluginData: plugin.serialize(data),
          pluginVersion: plugin.manifest.card.schemaVersion,
        } as Partial<PluginCard>)
      }
      onRegionChange={onRegionChange}
      onCancel={() => {
        transactionActive.current = false
        overlay.cancelMutation()
        onClose()
      }}
    />
  )
}

export function NotebookDetail({ notebookId }: { notebookId: string }) {
  const canvasRef = useRef<EndlessCanvasHandle>(null)
  const notebookRef = useRef<NotebookDocument | null>(null)
  const canvasStateRef = useRef<EndlessCanvasState | null>(null)
  const saveTimerRef = useRef<number | null>(null)
  const saveQueueRef = useRef<Promise<boolean>>(Promise.resolve(true))
  const mutationVersionRef = useRef(0)
  const persistedVersionRef = useRef(0)
  const pendingCardRef = useRef<{
    cardId: string
    data?: Record<string, unknown>
  }>({ cardId: "blank" })
  const activeLayerRef = useRef("main")
  const paneDepthRef = useRef(0)
  const rememberedToolsRef = useRef<Partial<Record<CanvasToolGroupId, CanvasTool>>>({
    shapes: "rect",
    connector: "arrow",
    text: "text",
    image: "image",
  })
  const allowCloseRef = useRef(false)
  const [notebook, setNotebook] = useState<NotebookDocument | null>(null)
  const [notebooks, setNotebooks] = useState<NotebookSummary[]>([])
  const [canvasState, setCanvasState] = useState<EndlessCanvasState | null>(null)
  const [tool, setTool] = useState<CanvasTool>("select")
  const [pane, setPane] = useState<CanvasPaneContext>({
    stackLevel: 0,
    cardPath: [],
    canGoBack: false,
    maxPaneDepth: 1,
  })
  const [panelOpen, setPanelOpen] = useState(false)
  const [zoom, setZoom] = useState(1)
  const [rememberedCardId, setRememberedCardId] = useState("blank")
  const [activeCardId, setActiveCardId] = useState<string | null>(null)
  const [inlinePluginEditor, setInlinePluginEditor] =
    useState<InlinePluginEditorState | null>(null)
  const [cardEditor, setCardEditor] = useState<CardEditorState | null>(null)
  const [cardEditorWindowOpen, setCardEditorWindowOpen] = useState(false)
  const [tierPreviewTasks, setTierPreviewTasks] = useState<TierPreviewTask[]>([])
  const tierPreviewKeysRef = useRef(new Map<string, string>())
  const cardEditorSaveHandlerRef = useRef<
    | ((
        cardId: string,
        tiers: CanvasCardTier[],
        previews: CardTierPreview[],
      ) => Promise<void>)
    | null
  >(null)
  const [pluginRevision, setPluginRevision] = useState(0)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [loadState, setLoadState] = useState<NotebookLoadState>({
    progress: 6,
    label: "Opening notebook…",
    error: null,
    visible: true,
  })

  const closeWindow = useCallback(() => {
    if (!isTauri) {
      window.close()
      return
    }
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) => getCurrentWindow().close())
      .catch(() => window.close())
  }, [])

  const saveNow = useCallback(function flushNotebook(): Promise<boolean> {
    if (saveTimerRef.current !== null) window.clearTimeout(saveTimerRef.current)
    saveTimerRef.current = null
    const requestedVersion = mutationVersionRef.current
    const operation = saveQueueRef.current.then(async () => {
      if (persistedVersionRef.current >= requestedVersion) return true
      const current = notebookRef.current
      const state = canvasStateRef.current
      if (!current || !state) return true
      const savingVersion = mutationVersionRef.current
      try {
        const summary = await notebookData.save({
          id: current.id,
          title: current.title,
          project: current.project,
          canvasType: "notebook",
          icon: current.icon,
          starred: current.starred,
          coverMediaId: current.coverMediaId,
          expectedRevision: current.revision,
          canvas: canvasToSnapshot(state),
        })
        let previewDataUrl = summary.previewDataUrl
        try {
          previewDataUrl =
            (await canvasRef.current?.captureSnapshot({
              format: "jpeg",
              quality: 0.72,
              resolution: 0.35,
            })) ?? previewDataUrl
          if (previewDataUrl) await notebookData.savePreview(current.id, previewDataUrl)
        } catch {
          // Saving notebook content is authoritative; a preview may be regenerated later.
        }
        const next = { ...current, ...summary, previewDataUrl }
        notebookRef.current = next
        setNotebook(next)
        persistedVersionRef.current = savingVersion
        return true
      } catch (error) {
        console.error(error)
        toast({
          title: "Couldn’t save notebook",
          description: error instanceof Error ? error.message : String(error),
        })
        return false
      }
    })
    saveQueueRef.current = operation
    return operation
  }, [])

  const scheduleSave = useCallback(
    (state: EndlessCanvasState) => {
      mutationVersionRef.current += 1
      canvasStateRef.current = state
      if (saveTimerRef.current !== null) window.clearTimeout(saveTimerRef.current)
      saveTimerRef.current = window.setTimeout(() => void saveNow(), 650)
    },
    [saveNow],
  )

  const enqueueTierPreviews = useCallback(
    (objects: readonly CanvasObject[], force = false) => {
      const tasks = objects
        .filter((object): object is CanvasCardObject => object.type === "card")
        .flatMap((card) => {
          const key = `${card.id}:${card.tiers
            .map((tier) => `${tier.id}:${tier.revision}`)
            .join("|")}`
          if (!force && tierPreviewKeysRef.current.get(card.id) === key) return []
          tierPreviewKeysRef.current.set(card.id, key)
          return [
            {
              key,
              card: canvasObjectFactory.hydrate(
                structuredClone(card),
              ) as CanvasCardObject,
            },
          ]
        })
      if (tasks.length === 0) return
      setTierPreviewTasks((current) => {
        const byId = new Map(current.map((task) => [task.card.id, task]))
        for (const task of tasks) byId.set(task.card.id, task)
        return [...byId.values()]
      })
    },
    [],
  )

  const handleCanvasChange = useCallback(
    (state: EndlessCanvasState) => {
      scheduleSave(state)
      enqueueTierPreviews(state.objects)
    },
    [enqueueTierPreviews, scheduleSave],
  )

  const refreshPlugins = useCallback(async () => {
    const installations = await pluginData.list()
    notesPlugins.setInstallations(
      installations.filter((item) => item.installed).map((item) => item.pluginId),
    )
    setPluginRevision((value) => value + 1)
  }, [])

  useEffect(() => {
    let cancelled = false
    let completedFetches = 0
    setNotebook(null)
    setCanvasState(null)
    setTierPreviewTasks([])
    tierPreviewKeysRef.current.clear()
    notebookRef.current = null
    canvasStateRef.current = null
    setLoadState({
      progress: 6,
      label: "Opening notebook…",
      error: null,
      visible: true,
    })
    const track = async <T,>(promise: Promise<T>, label: string): Promise<T> => {
      const value = await promise
      completedFetches += 1
      if (!cancelled) {
        const progress = 12 + completedFetches * 18
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, progress),
          label,
        }))
      }
      return value
    }
    void Promise.all([
      track(notebookData.get(notebookId), "Notebook loaded"),
      track(notebookData.list(), "Notebook index loaded"),
      track(pluginData.list(), "Card plugins loaded"),
      track(personData.list(), "People loaded"),
    ])
      .then(([stored, all, installations, people]) => {
        if (cancelled) return
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, 76),
          label: "Preparing cards…",
        }))
        notesPlugins.setInstallations(
          installations.filter((item) => item.installed).map((item) => item.pluginId),
        )
        notesPlugins.setPersons(people)
        setPluginRevision((value) => value + 1)
        const migratedRootArrows = stored
          ? migrateNotebookRootArrows(stored.canvas)
          : false
        const initialState = stored
          ? snapshotToCanvas(stored.canvas)
          : createEmptyNotebookState()
        const migratedQuestions = migrateLegacyQuestionCards(initialState.objects)
        const migratedCards = notesPlugins.migrateCards(initialState.objects)
        const migratedTextStyles = migrateLegacyNotebookTextStyles(initialState.objects)
        const document = stored ?? {
          id: notebookId,
          title: "Untitled notebook",
          project: "My notebooks",
          canvasType: "notebook" as const,
          icon: "📓",
          starred: false,
          createdAt: Date.now(),
          updatedAt: Date.now(),
          revision: 0,
          previewDataUrl: null,
          coverMediaId: null,
          canvas: canvasToSnapshot(initialState),
        }
        notebookRef.current = document
        canvasStateRef.current = initialState
        activeLayerRef.current = initialState.activeLayerId ?? "main"
        setZoom(initialState.viewport?.scale ?? 1)
        setNotebook(document)
        setNotebooks(all)
        setCanvasState(initialState)
        enqueueTierPreviews(initialState.objects, true)
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, 92),
          label: "Starting canvas…",
        }))
        if (
          migratedQuestions ||
          migratedCards ||
          migratedRootArrows ||
          migratedTextStyles
        )
          scheduleSave(initialState)
      })
      .catch((error: unknown) => {
        if (cancelled) return
        setLoadState((current) => ({
          ...current,
          error: error instanceof Error ? error.message : String(error),
          label: "Couldn’t open this notebook",
          visible: true,
        }))
      })
    return () => {
      cancelled = true
    }
  }, [enqueueTierPreviews, loadAttempt, notebookId, scheduleSave])

  const handleCanvasReady = useCallback(() => {
    setLoadState((current) => ({
      ...current,
      progress: 100,
      label: "Notebook ready",
      error: null,
      visible: true,
    }))
    window.setTimeout(
      () => setLoadState((current) => ({ ...current, visible: false })),
      180,
    )
  }, [])

  useEffect(() => {
    const initialFocus = new URLSearchParams(window.location.search).get("focus")
    let unlisten: (() => void) | undefined
    const focus = (objectId: string | null) => {
      if (objectId)
        window.requestAnimationFrame(() => canvasRef.current?.focusObject(objectId))
    }
    focus(initialFocus)
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen<string>("notes:focus-object", (event) => focus(event.payload)),
      )
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => unlisten?.()
  }, [canvasState])

  useEffect(() => {
    let unlisten: (() => void) | undefined
    const refresh = () => void refreshPlugins()
    window.addEventListener("notes:plugins-changed", refresh)
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:plugins-changed", refresh))
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => {
      unlisten?.()
      window.removeEventListener("notes:plugins-changed", refresh)
    }
  }, [refreshPlugins])

  useEffect(() => {
    let unlisten: (() => void) | undefined
    const refresh = () => {
      void personData.list().then((people) => {
        notesPlugins.setPersons(people)
        setPluginRevision((value) => value + 1)
      })
    }
    window.addEventListener("notes:persons-changed", refresh)
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:persons-changed", refresh))
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => {
      unlisten?.()
      window.removeEventListener("notes:persons-changed", refresh)
    }
  }, [])

  useEffect(() => {
    if (!isTauri) return undefined
    let unlisten: (() => void) | undefined
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) =>
        getCurrentWindow().onCloseRequested(async (event) => {
          if (allowCloseRef.current) return
          event.preventDefault()
          await saveNow()
          allowCloseRef.current = true
          await getCurrentWindow().destroy()
        }),
      )
      .then((dispose) => {
        unlisten = dispose
      })
    return () => unlisten?.()
  }, [saveNow])

  useEffect(() => {
    if (!isTauri) return undefined
    let unlisten: (() => void) | undefined
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) =>
        getCurrentWindow().listen<CardEditorSaveRequest>(
          "notes:card-editor-save-request",
          async ({ payload }) => {
            try {
              const save = cardEditorSaveHandlerRef.current
              if (!save) throw new Error("Notebook is not ready to save cards.")
              await save(payload.cardId, payload.tiers, payload.previews)
              await cardEditorWindows.resolveSave({
                sessionId: payload.sessionId,
                requestId: payload.requestId,
                succeeded: true,
              })
            } catch (error) {
              await cardEditorWindows.resolveSave({
                sessionId: payload.sessionId,
                requestId: payload.requestId,
                succeeded: false,
                error: error instanceof Error ? error.message : String(error),
              })
            }
          },
        ),
      )
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(console.error)
    return () => unlisten?.()
  }, [])

  useEffect(() => {
    if (!isTauri) return undefined
    let unlisten: (() => void) | undefined
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) =>
        getCurrentWindow().listen<CardEditorLifecycle>(
          "notes:card-editor-lifecycle",
          ({ payload }) => {
            if (payload.notebookId === notebookId)
              setCardEditorWindowOpen(payload.open)
          },
        ),
      )
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(console.error)
    return () => unlisten?.()
  }, [notebookId])

  useEffect(
    () => () => {
      if (saveTimerRef.current !== null) window.clearTimeout(saveTimerRef.current)
      notesPlugins.dispose()
    },
    [],
  )

  const handlePaneChange = useCallback((context: CanvasPaneContext) => {
    paneDepthRef.current = context.stackLevel
    setPane(context)
    setTool("select")
  }, [])
  const handleLayersChange = useCallback((api: { activeLayerId: string }) => {
    activeLayerRef.current = api.activeLayerId
  }, [])
  const handleViewportChange = useCallback(
    (viewport: EndlessCanvasState["viewport"]) => {
      setZoom(viewport?.scale ?? 1)
    },
    [],
  )
  const selectTool = useCallback((nextTool: CanvasTool) => {
    setActiveCardId(null)
    if (nextTool === "image" || nextTool === "video") {
      setTool("select")
      if (nextTool === "image") canvasRef.current?.insertImage()
      else canvasRef.current?.insertVideo()
      return
    }
    setTool(nextTool)
    const group = groupForTool(nextTool)
    if (group) rememberedToolsRef.current[group] = nextTool
  }, [])
  const handleToolChangeRequest = selectTool

  const armCard = useCallback((cardId: string, data?: Record<string, unknown>) => {
    setRememberedCardId(cardId)
    pendingCardRef.current = { cardId, data }
    setActiveCardId(cardId)
    setTool("add")
  }, [])

  const enabledTools = toolsForNotebookDepth(pane.stackLevel)
  const pluginCards = useMemo(() => {
    void pluginRevision
    return notesPlugins.availableCards()
  }, [pluginRevision])
  const cardItems = useMemo(
    () => [
      {
        id: "blank",
        label: "Blank",
        icon: <Square />,
        selected: rememberedCardId === "blank",
        onSelect: () => armCard("blank"),
      },
      {
        id: "markdown",
        label: "Markdown",
        icon: <MarkdownToolIcon />,
        selected: rememberedCardId === "markdown",
        onSelect: () => armCard("markdown"),
      },
      ...pluginCards.map((card) => {
        const ToolbarIcon = card.slots.ToolbarIcon
        return {
          id: card.manifest.id,
          label: card.manifest.name,
          icon: <ToolbarIcon />,
          selected: rememberedCardId === card.manifest.id,
          onSelect: () => armCard(card.manifest.id),
        }
      }),
    ],
    [armCard, pluginCards, rememberedCardId],
  )

  useEffect(() => {
    if (cardItems.some((item) => item.id === rememberedCardId)) return
    setRememberedCardId("blank")
    pendingCardRef.current = { cardId: "blank" }
    setActiveCardId(null)
    if (tool === "add") setTool("select")
  }, [cardItems, rememberedCardId, tool])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (
        event.repeat ||
        event.metaKey ||
        event.ctrlKey ||
        event.altKey ||
        event.target instanceof HTMLInputElement ||
        event.target instanceof HTMLTextAreaElement ||
        event.target instanceof HTMLSelectElement ||
        (event.target instanceof HTMLElement && event.target.isContentEditable) ||
        document.querySelector(
          "[data-slot='dialog-content'], [data-slot='dropdown-menu-content']",
        )
      )
        return
      if (event.key.toLowerCase() === "c" && paneDepthRef.current === 0) {
        const next = nextCustomMenuItem(
          cardItems,
          tool === "add" || tool === "markdown-card" ? activeCardId : null,
          rememberedCardId,
          event.shiftKey ? -1 : 1,
        )
        if (next) {
          event.preventDefault()
          next.onSelect()
        }
        return
      }
      const group = groupForShortcut(event.key, enabledTools)
      if (!group) return
      event.preventDefault()
      selectTool(
        nextToolForGroup(
          group,
          tool,
          rememberedToolsRef.current[group],
          enabledTools,
          event.shiftKey ? -1 : 1,
        ),
      )
    }
    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [activeCardId, cardItems, enabledTools, rememberedCardId, selectTool, tool])

  const placeCard = useCallback(
    (
      point: CanvasPoint,
      _bounds?: { x: number; y: number; width: number; height: number },
    ): CanvasObject | null => {
      const pending = pendingCardRef.current
      if (!pending || paneDepthRef.current !== 0) return null
      setTool("select")
      setActiveCardId(null)
      if (pending.cardId === "blank") {
        const width = 220
        const height = 140
        const card = new IllustrationCard({
          id: crypto.randomUUID(),
          layerId: activeLayerRef.current,
          type: "card",
          kind: "canvas",
          x: point.x - width / 2,
          y: point.y - height / 2,
          width,
          height,
          elements: [],
          backgroundColor: 0xffffff,
        })
        window.requestAnimationFrame(() =>
          isTauri
            ? void cardEditorWindows
                .open({
                  notebookId,
                  notebookTitle: notebookRef.current?.title ?? "Notebook",
                  cardId: card.id,
                  tiers: structuredClone(card.tiers),
                })
                .catch((error) =>
                  toast({
                    title: "Couldn’t open card editor",
                    description: error instanceof Error ? error.message : String(error),
                  }),
                )
            : setCardEditor({
                kind: "blank",
                cardId: card.id,
                tiers: structuredClone(card.tiers),
              }),
        )
        return card
      }
      if (pending.cardId === "markdown") {
        const width = 220
        const height = 140
        return new MarkdownCard({
          id: crypto.randomUUID(),
          layerId: activeLayerRef.current,
          type: "card",
          kind: "markdown",
          x: point.x - width / 2,
          y: point.y - height / 2,
          width,
          height,
          elements: [],
          markdown: "",
          backgroundColor: 0xffffff,
        })
      }
      const plugin = notesPlugins.definition(pending.cardId)
      if (!plugin || !notesPlugins.isInstalled(pending.cardId)) return null
      const card = plugin.create({
        notebookId,
        layerId: activeLayerRef.current,
        point,
      })
      if (pending.data) card.pluginData = { ...card.pluginData, ...pending.data }
      plugin.normalizeCard?.(card)
      pendingCardRef.current = { cardId: pending.cardId }
      if (plugin.slots.Editor) {
        setCardEditor({
          kind: "plugin",
          mode: "create",
          plugin,
          point,
          initialData: card.pluginData,
        })
        return null
      }
      return card
    },
    [notebookId],
  )

  const placeDrawnCard = useCallback(
    (placement: CanvasDrawnPlacement) =>
      placeCard(placement.center, placement.dragged ? placement.bounds : undefined),
    [placeCard],
  )

  const resolveArrowDefaults = useCallback(
    (arrowTool: "arrow" | "line", context: CanvasPaneContext) =>
      context.stackLevel === 0 && arrowTool === "arrow"
        ? { stroke: 0x7c3aed, strokeWidth: 4 }
        : undefined,
    [],
  )

  const canvasAssets = useMemo(createNotesCanvasAssets, [])
  const pluginServices = useMemo(
    () => notesPlugins.hostServices(notebookId),
    [notebookId],
  )
  const nativeClipboard = useMemo(createTauriCanvasClipboard, [])

  const pluginCardExtension = useMemo<CanvasObjectExtension<PluginCard>>(
    () => ({
      type: "card",
      selectionGeometry: (card) => {
        if (card.kind !== "plugin") return null
        const adapter = notesPlugins.definition(card.pluginId)?.slots.InlineEditor
        return adapter?.suppressCardSelection ? { shape: "none" } : null
      },
      minimumSize: (card) => {
        if (card.kind !== "plugin") return null
        const plugin = notesPlugins.definition(card.pluginId)
        if (!plugin?.slots.InlineEditor) return null
        return {
          width: plugin.manifest.card.defaultDimensions.width,
          height: plugin.manifest.card.defaultDimensions.height,
        }
      },
      pointerInteractionRegions: (card) => {
        if (card.kind !== "plugin") return []
        return (
          notesPlugins.definition(card.pluginId)?.slots.InlineEditor?.regions(card) ??
          []
        )
      },
    }),
    [],
  )

  const openTierEditor = useCallback(
    (card: CanvasCardObject) => {
      const tiers = structuredClone(card.tiers).map((tier) => ({
        ...tier,
        elements: tier.elements.map((element) => canvasObjectFactory.hydrate(element)),
      }))
      if (!isTauri) {
        setCardEditor({ kind: "blank", cardId: card.id, tiers })
        return
      }
      void cardEditorWindows
        .open({
          notebookId,
          notebookTitle: notebookRef.current?.title ?? "Notebook",
          cardId: card.id,
          tiers,
        })
        .catch((error) =>
          toast({
            title: "Couldn’t open card editor",
            description: error instanceof Error ? error.message : String(error),
          }),
        )
    },
    [notebookId],
  )

  const createPastedImageCard = useCallback<
    NonNullable<EndlessCanvasOptions["onExternalImagePaste"]>
  >(
    async (input) => {
      const media = await importNotebookImage(notebookId, {
        dataUrl: input.dataUrl,
        name: input.name,
        mimeType: input.mimeType,
        width: input.width,
        height: input.height,
      })
      const sourceWidth = media.width ?? input.width
      const sourceHeight = media.height ?? input.height
      const scale = Math.min(1, 320 / Math.max(sourceWidth, sourceHeight))
      const imageWidth = sourceWidth * scale
      const imageHeight = sourceHeight * scale
      const padding = 12
      const cardWidth = Math.max(minCardWidth, imageWidth + padding * 2)
      const cardHeight = Math.max(minCardHeight, imageHeight + padding * 2)
      const image = new ImageObject({
        id: crypto.randomUUID(),
        layerId: input.layerId,
        type: "image",
        x: (cardWidth - imageWidth) / 2,
        y: (cardHeight - imageHeight) / 2,
        width: imageWidth,
        height: imageHeight,
        rotation: 0,
        opacity: 1,
        src: media.url,
        previewSrc: notebookMediaUrl(media.id, "thumbnail"),
        name: media.name,
        sourceWidth,
        sourceHeight,
        uploadStatus: "ready",
        lockAspectRatio: true,
        cornerRadius: 6,
      })
      return new IllustrationCard({
        id: crypto.randomUUID(),
        layerId: input.layerId,
        type: "card",
        kind: "canvas",
        x: input.point.x - cardWidth / 2,
        y: input.point.y - cardHeight / 2,
        width: cardWidth,
        height: cardHeight,
        elements: [image],
        backgroundColor: 0xffffff,
      })
    },
    [notebookId],
  )

  const options = useMemo<EndlessCanvasOptions>(
    () => ({
      maxPaneDepth: 1,
      pluginCards: notesPlugins,
      objectExtensions: [pluginCardExtension],
      objectCapabilities: { card: { resizable: false, rotatable: false } },
      preserveCardDimensions: true,
      onAddToolDraw: placeDrawnCard,
      resolveArrowDefaults,
      canInsertObject: allowsNotebookInsertion,
      shouldEnterCardPane: () => false,
      clipboard: nativeClipboard,
      onExternalImagePaste: createPastedImageCard,
      onObjectCreate: (object, context) => {
        applyNotebookRootArrowStyle(object, context)
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin") return
        const card = object as PluginCard
        const definition = notesPlugins.definition(card.pluginId)
        void definition?.lifecycle.onCreate?.({ notebookId, cardId: card.id })
        const inline = definition?.slots.InlineEditor
        if (inline) {
          window.requestAnimationFrame(() =>
            setInlinePluginEditor({
              cardId: card.id,
              regionId: inline.initialRegion(card),
            }),
          )
        }
      },
      onObjectDelete: (object) => {
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin") return
        const card = object as PluginCard
        void notesPlugins
          .definition(card.pluginId)
          ?.lifecycle.onDelete?.({ notebookId, cardId: card.id })
      },
      onObjectClick: (object, context) => {
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin") return
        const card = object as PluginCard
        const inline = notesPlugins.definition(card.pluginId)?.slots.InlineEditor
        if (!inline) return
        setInlinePluginEditor({
          cardId: card.id,
          regionId: context.regionId ?? inline.initialRegion(card),
        })
      },
      onSelectionChange: (selection) => {
        setInlinePluginEditor((current) =>
          current && selection.selectedIds.includes(current.cardId) ? current : null,
        )
      },
      onObjectActivate: (object) => {
        if (object.type !== "card") return
        const genericCard = object as CanvasCardObject
        if (genericCard.kind === "canvas") {
          openTierEditor(genericCard)
          return
        }
        if (genericCard.kind !== "plugin") return
        const card = object as PluginCard
        const definition = notesPlugins.definition(card.pluginId)
        if (definition?.slots.InlineEditor) {
          setInlinePluginEditor({
            cardId: card.id,
            regionId: definition.slots.InlineEditor.initialRegion(card),
          })
          return
        }
        if (card.pluginId === "notes.notebook-card") {
          const target = String(card.pluginData.targetNotebookId ?? "")
          const title = String(card.pluginData.targetNotebookTitle ?? "Notebook")
          if (target) void notebookData.open(target, title)
          void definition?.lifecycle.onActivate?.({
            notebookId,
            cardId: card.id,
          })
          return
        }
        if (definition?.slots.Editor && notesPlugins.isInstalled(card.pluginId)) {
          setCardEditor({
            kind: "plugin",
            mode: "edit",
            plugin: definition,
            cardId: card.id,
            initialData: card.pluginData,
          })
        }
        void definition?.lifecycle.onActivate?.({
          notebookId,
          cardId: card.id,
        })
      },
      assets: canvasAssets,
    }),
    [
      canvasAssets,
      createPastedImageCard,
      nativeClipboard,
      notebookId,
      placeDrawnCard,
      pluginCardExtension,
      resolveArrowDefaults,
      openTierEditor,
    ],
  )

  const toggleFavorite = useCallback(() => {
    const current = notebookRef.current
    if (!current) return
    const next = { ...current, starred: !current.starred }
    notebookRef.current = next
    setNotebook(next)
    if (canvasStateRef.current) scheduleSave(canvasStateRef.current)
  }, [scheduleSave])

  const exportNotebook = useCallback(() => {
    const current = notebookRef.current
    const state = canvasStateRef.current
    if (!current || !state) return
    const blob = new Blob(
      [JSON.stringify({ ...current, canvas: canvasToSnapshot(state) }, null, 2)],
      { type: "application/json" },
    )
    const link = document.createElement("a")
    link.href = URL.createObjectURL(blob)
    link.download = `${current.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase() || "notebook"}.notes.json`
    link.click()
    URL.revokeObjectURL(link.href)
  }, [])

  useEffect(() => {
    if (!isTauri) return undefined
    let dispose: (() => void)[] = []
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        Promise.all([
          listen("notes:native-toggle-favorite", toggleFavorite),
          listen("notes:native-export-notebook", exportNotebook),
          listen("notes:native-toggle-notebook-panel", () =>
            setPanelOpen((value) => !value),
          ),
        ]),
      )
      .then((listeners) => {
        dispose = listeners
      })
      .catch(console.error)
    return () => dispose.forEach((listener) => listener())
  }, [exportNotebook, toggleFavorite])

  if (loadState.error) {
    return (
      <main className="detail-loading" role="alert">
        <div className="detail-loading-card">
          <AlertTriangle aria-hidden="true" />
          <h1>Couldn’t open this notebook</h1>
          <p>{loadState.error}</p>
          <div className="detail-loading-actions">
            <Button
              type="button"
              onClick={() => setLoadAttempt((attempt) => attempt + 1)}
            >
              <RefreshCw /> Retry
            </Button>
            <Button type="button" variant="outline" onClick={closeWindow}>
              <X /> Close
            </Button>
          </div>
        </div>
      </main>
    )
  }

  if (!notebook || !canvasState) {
    return (
      <main className="detail-loading" aria-busy="true" aria-live="polite">
        <div className="detail-loading-card">
          <Progress value={loadState.progress} aria-label={loadState.label} />
        </div>
      </main>
    )
  }

  const setMetadata = (
    patch: Partial<
      Pick<NotebookDocument, "title" | "project" | "icon" | "coverMediaId">
    >,
  ) => {
    const next = { ...notebookRef.current!, ...patch }
    notebookRef.current = next
    setNotebook(next)
    if (canvasStateRef.current) scheduleSave(canvasStateRef.current)
  }
  const setCoverImage = async (input: CardPluginImageInput) => {
    const media = await importNotebookImage(notebook.id, input)
    setMetadata({ coverMediaId: media.id })
  }
  const saveBlankCard = async (
    cardId: string,
    tiers: CanvasCardTier[],
    previews: Array<{
      tierId: string
      tierRevision: number
      dataUrl: string
    }>,
  ) => {
    const existing = canvasStateRef.current?.objects.find(
      (object) => object.id === cardId && object.type === "card",
    ) as CanvasCardObject | undefined
    if (!existing) throw new Error("This card is no longer in the notebook.")
    const normalizedTiers = structuredClone(tiers).map((tier) => {
      const stored = existing.tiers.find((candidate) => candidate.id === tier.id)
      return {
        ...tier,
        width: stored?.width ?? existing.width,
        height: stored?.height ?? existing.height,
        elements: tier.elements.map((element) =>
          canvasObjectFactory.hydrate({
            ...element,
            layerId: existing.layerId,
          } as CanvasObject),
        ),
      }
    })
    const fixed = canvasObjectFactory.hydrate({
      ...structuredClone(existing),
      tiers: normalizedTiers,
    } as unknown as CanvasObject) as CanvasCardObject
    canvasRef.current?.updateObject(existing.id, {
      tiers: fixed.tiers,
    } as Partial<CanvasCardObject>)
    await notebookData.saveCardTierPreviews(
      previews.map((preview) => ({
        documentId: notebook.id,
        cardId: existing.id,
        ...preview,
      })),
    )
    if (!(await saveNow())) throw new Error("Couldn’t save card changes.")
  }
  cardEditorSaveHandlerRef.current = saveBlankCard
  const savePluginCard = (data: Record<string, unknown>) => {
    if (!cardEditor || cardEditor.kind !== "plugin") return
    if (cardEditor.mode === "create") {
      const card = cardEditor.plugin.create({
        notebookId,
        layerId: activeLayerRef.current,
        point: cardEditor.point ?? { x: 0, y: 0 },
      })
      card.pluginData = data
      card.pluginVersion = cardEditor.plugin.manifest.card.schemaVersion
      canvasRef.current?.insertObject(card)
    } else if (cardEditor.cardId) {
      canvasRef.current?.updateObject(cardEditor.cardId, {
        pluginData: data,
        pluginVersion: cardEditor.plugin.manifest.card.schemaVersion,
      } as Partial<PluginCard>)
    }
    setCardEditor(null)
  }
  const cardMenu =
    pane.stackLevel === 0
      ? {
          label: "Cards",
          icon: <Square />,
          shortcut: "c",
          active: ["card", "markdown-card", "add"].includes(tool),
          onPrimarySelect: () => armCard(rememberedCardId),
          items: cardItems,
        }
      : undefined
  return (
    <div className="detail-shell">
      <div className="detail-workspace" inert={cardEditorWindowOpen ? true : undefined}>
        <WorkspaceDocumentHeader
          className="detail-document-header absolute inset-x-0 top-0"
          icon={<IconGlyph name={notebook.icon || "file-text"} />}
          title={notebook.title}
        />
        <CanvasSurfaceContextMenu
          canvasRef={canvasRef}
          onOpenMedia={(mediaId) => notebookMediaData.open(mediaId)}
          onError={console.error}
        >
          <div className="detail-canvas-surface">
            <EndlessCanvas
            ref={canvasRef}
            className="canvas-endless-canvas"
            tool={tool}
            initialState={canvasState}
            options={options}
            onChange={handleCanvasChange}
            onToolChangeRequest={handleToolChangeRequest}
            onPaneChange={handlePaneChange}
            onLayersChange={handleLayersChange}
            onViewportChange={handleViewportChange}
            onReady={handleCanvasReady}
            layersSlot={(api) => (
              <NotebookPanel
                {...api}
                notebook={notebook}
                open={panelOpen}
                onMetadata={setMetadata}
                onCoverImage={setCoverImage}
              />
            )}
            propertiesSlot={(props) => {
              const object =
                props.selection.selectedObjects.length === 1
                  ? props.selection.selectedObjects[0]
                  : null
              const card =
                object?.type === "card" && (object as PluginCard).kind === "plugin"
                  ? (object as PluginCard)
                  : null
              const plugin = card ? notesPlugins.definition(card.pluginId) : null
              return (
                <DiscreteProperties
                  {...props}
                  plugin={plugin}
                  pluginInstalled={
                    card ? notesPlugins.isInstalled(card.pluginId) : false
                  }
                  notebooks={notebooks}
                  onEditTiers={openTierEditor}
                />
              )
            }}
            objectOverlaySlot={(overlay) => {
              if (
                !inlinePluginEditor ||
                overlay.object.id !== inlinePluginEditor.cardId ||
                overlay.object.type !== "card" ||
                (overlay.object as PluginCard).kind !== "plugin"
              )
                return null
              const card = overlay.object as PluginCard
              const plugin = notesPlugins.definition(card.pluginId)
              if (!plugin?.slots.InlineEditor) return null
              return (
                <PluginInlineEditorOverlay
                  overlay={overlay}
                  plugin={plugin}
                  regionId={inlinePluginEditor.regionId}
                  onRegionChange={(regionId) =>
                    setInlinePluginEditor({ cardId: card.id, regionId })
                  }
                  onClose={() => setInlinePluginEditor(null)}
                />
              )
            }}
            />
          </div>
        </CanvasSurfaceContextMenu>
      </div>
      {cardEditorWindowOpen && (
        <div className="detail-card-editor-shield" aria-hidden="true" />
      )}
      {loadState.visible && (
        <div
          className="detail-loading detail-loading-overlay"
          aria-busy="true"
          aria-live="polite"
        >
          <div className="detail-loading-card">
            <Progress value={loadState.progress} aria-label={loadState.label} />
          </div>
        </div>
      )}
      <CanvasToolbar
        tool={tool}
        onToolChange={selectTool}
        enabledTools={enabledTools}
        cardMenu={cardMenu}
        iconOverrides={{
          markdown: <MarkdownToolIcon />,
          "markdown-card": <MarkdownToolIcon />,
        }}
      />
      {cardEditor?.kind === "blank" && (
        <BlankCardEditorDialog
          key={cardEditor.cardId}
          initialTiers={cardEditor.tiers}
          assets={canvasAssets}
          onSave={(tiers, previews) =>
            saveBlankCard(cardEditor.cardId, tiers, previews)
          }
          onClose={() => setCardEditor(null)}
        />
      )}
      {tierPreviewTasks[0] && (
        <CardTierPreviewRegenerator
          key={tierPreviewTasks[0].key}
          notebookId={notebook.id}
          card={tierPreviewTasks[0].card}
          options={options}
          onComplete={() => {
            const completed = tierPreviewTasks[0]
            setTierPreviewTasks((current) =>
              current.filter((task) => task.key !== completed.key),
            )
          }}
        />
      )}
      {cardEditor?.kind === "plugin" && (
        <CardEditorDialog
          key={`${cardEditor.plugin.manifest.id}-${cardEditor.mode}-${cardEditor.cardId ?? "new"}`}
          plugin={cardEditor.plugin}
          mode={cardEditor.mode}
          initialData={cardEditor.initialData}
          services={pluginServices}
          onSave={savePluginCard}
          onCancel={() => setCardEditor(null)}
        />
      )}
      {pane.canGoBack && (
        <button
          type="button"
          className="pane-back"
          onClick={() => canvasRef.current?.exitPane()}
        >
          ← Back to notebook
        </button>
      )}
      {pane.stackLevel === 0 && !panelOpen && !loadState.visible && !cardEditor && (
        <CanvasMinimap canvasRef={canvasRef} className="notebook-minimap" />
      )}
      <div className="zoom-controls">
        <button type="button" onClick={() => canvasRef.current?.zoomBy(-0.1)}>
          −
        </button>
        <span>{Math.round(zoom * 100)}%</span>
        <button type="button" onClick={() => canvasRef.current?.zoomBy(0.1)}>
          +
        </button>
      </div>
    </div>
  )
}
