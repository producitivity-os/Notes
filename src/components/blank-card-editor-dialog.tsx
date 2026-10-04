import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react"
import {
  ArrowDown,
  ArrowUp,
  ChevronLeft,
  ChevronRight,
  Plus,
  Trash2,
} from "@productivity-os/shared-ui/components/sf-symbols"
import {
  CanvasToolbar,
  CanvasSurfaceContextMenu,
  EndlessCanvas,
  canvasObjectFactory,
  createCanvasCardTier,
  groupForShortcut,
  groupForTool,
  nextToolForGroup,
  type CanvasCardTier,
  type CanvasObject,
  type CanvasTool,
  type CanvasToolGroupId,
  type EndlessCanvasHandle,
  type EndlessCanvasOptions,
  type EndlessCanvasState,
} from "@productivity-os/canvas"
import { Button } from "@productivity-os/shared-ui/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@productivity-os/shared-ui/components/ui/dialog"
import { toolsForNotebookDepth } from "@/canvas/notebook-policy"
import { MarkdownToolIcon } from "@/components/markdown-tool-icon"
import { createTauriCanvasClipboard } from "@/api/tauri-canvas-clipboard"

type Props = {
  initialTiers: readonly CanvasCardTier[]
  assets: NonNullable<EndlessCanvasOptions["assets"]>
  standalone?: boolean
  onSave(
    tiers: CanvasCardTier[],
    previews: Array<{
      tierId: string
      tierRevision: number
      dataUrl: string
    }>,
  ): void | Promise<void>
  onClose(): void | Promise<void>
}

type TierPreview = {
  tierId: string
  tierRevision: number
  dataUrl: string
}

export type BlankCardEditorHandle = {
  requestClose(): Promise<void>
}

const AUTOSAVE_DELAY = 1_500

const layerId = (tierId: string) => `card-editor-${tierId}`

function cloneTier(tier: CanvasCardTier): CanvasCardTier {
  const editorLayer = layerId(tier.id)
  return {
    ...structuredClone(tier),
    elements: structuredClone(tier.elements).map((element) =>
      canvasObjectFactory.hydrate({ ...element, layerId: editorLayer } as CanvasObject),
    ),
  }
}

function stateFor(tier: CanvasCardTier): EndlessCanvasState {
  const id = layerId(tier.id)
  return {
    activeLayerId: id,
    focusedLayerId: null,
    unfocusedLayerOpacity: 1,
    viewport: { x: 0, y: 0, scale: 1 },
    layers: [
      {
        id,
        name: tier.name,
        zIndex: 0,
        visible: true,
        opacity: 1,
        interactionColor: 0x3b82f6,
      },
    ],
    objects: tier.elements,
  }
}

export const BlankCardEditorDialog = forwardRef<BlankCardEditorHandle, Props>(
  function BlankCardEditorDialog(
    { initialTiers, assets, standalone = false, onSave, onClose },
    ref,
  ) {
    const [tiers, setTiers] = useState<CanvasCardTier[]>(() =>
      initialTiers.map(cloneTier),
    )
    const tiersRef = useRef(tiers)
    const canvasRef = useRef<EndlessCanvasHandle>(null)
    const stageRef = useRef<HTMLDivElement>(null)
    const activeTierIdRef = useRef(initialTiers[0]?.id ?? "front")
    const previewCacheRef = useRef(new Map<string, TierPreview>())
    const navigationQueueRef = useRef<Promise<void>>(Promise.resolve())
    const timerRef = useRef<number | null>(null)
    const resizeTimerRef = useRef<number | null>(null)
    const closingRef = useRef(false)
    const mutationVersionRef = useRef(0)
    const persistedVersionRef = useRef(-1)
    const saveQueueRef = useRef<Promise<boolean>>(Promise.resolve(true))
    const [activeTierId, setActiveTierId] = useState(activeTierIdRef.current)
    const [saveError, setSaveError] = useState<string | null>(null)
    const rememberedRef = useRef<Partial<Record<CanvasToolGroupId, CanvasTool>>>({
      shapes: "rect",
      connector: "arrow",
      text: "markdown",
      image: "image",
    })
    const [tool, setTool] = useState<CanvasTool>("select")
    const enabledTools = useMemo(
      () => toolsForNotebookDepth(1).filter((candidate) => candidate !== "hand"),
      [],
    )
    const nativeClipboard = useMemo(createTauriCanvasClipboard, [])
    const options = useMemo<EndlessCanvasOptions>(
      () => ({
        maxPaneDepth: 0,
        assets,
        clipboard: nativeClipboard,
        defaultTextFormat: "markdown",
        viewportMode: "bounded",
        canInsertObject: (object) => object.type !== "card",
      }),
      [assets, nativeClipboard],
    )

    const snapshot = useCallback(
      () =>
        tiersRef.current.map((tier, index) => ({
          ...cloneTier(tier),
          id: index === 0 ? "front" : tier.id,
          name: index === 0 ? "Front" : tier.name,
          revision: tier.revision,
          elements: tier.elements.map((element) =>
            canvasObjectFactory.hydrate({
              ...structuredClone(element),
              layerId: initialTiers[0]?.elements[0]?.layerId ?? "main",
            } as CanvasObject),
          ),
        })),
      [initialTiers],
    )

    const captureActivePreview = useCallback(async () => {
      const tierId = activeTierIdRef.current
      const tier = tiersRef.current.find((candidate) => candidate.id === tierId)
      if (!tier || (tier.id === "front" && tier.kind !== "canvas")) return
      const dataUrl = await canvasRef.current?.captureSnapshot({
        format: "jpeg",
        quality: 0.8,
        resolution: 0.5,
      })
      if (!dataUrl) return
      previewCacheRef.current.set(tier.id, {
        tierId: tier.id,
        tierRevision: tier.revision,
        dataUrl,
      })
    }, [])

    const flush = useCallback(() => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current)
      timerRef.current = null
      setSaveError(null)
      const requestedVersion = mutationVersionRef.current
      const operation = saveQueueRef.current.then(async () => {
        if (persistedVersionRef.current >= requestedVersion) {
          return true
        }

        const savingVersion = mutationVersionRef.current
        try {
          await captureActivePreview()
          const next = snapshot()
          const currentRevisions = new Map(
            next.map((tier) => [tier.id, tier.revision]),
          )
          const previews = [...previewCacheRef.current.values()].filter(
            (preview) => currentRevisions.get(preview.tierId) === preview.tierRevision,
          )
          await onSave(next, previews)
          persistedVersionRef.current = savingVersion
          return true
        } catch (error) {
          console.error(error)
          setSaveError(
            error instanceof Error ? error.message : "Couldn’t save card changes.",
          )
          return false
        }
      })
      saveQueueRef.current = operation
      return operation
    }, [captureActivePreview, onSave, snapshot])

    const scheduleSave = useCallback(() => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current)
      timerRef.current = window.setTimeout(() => void flush(), AUTOSAVE_DELAY)
    }, [flush])

    const updateTiers = useCallback(
      (update: (current: CanvasCardTier[]) => CanvasCardTier[]) => {
        const next = update(tiersRef.current)
        if (next === tiersRef.current) return
        mutationVersionRef.current += 1
        tiersRef.current = next
        setTiers(next)
        scheduleSave()
      },
      [scheduleSave],
    )

    const selectTier = useCallback(
      (tierId: string) => {
        navigationQueueRef.current = navigationQueueRef.current.then(async () => {
          if (tierId === activeTierIdRef.current) return
          try {
            await captureActivePreview()
          } catch (error) {
            console.error(error)
          }
          if (!tiersRef.current.some((tier) => tier.id === tierId)) return
          activeTierIdRef.current = tierId
          setActiveTierId(tierId)
          setTool("select")
        })
      },
      [captureActivePreview],
    )

    const addTier = useCallback(() => {
      const id = crypto.randomUUID()
      navigationQueueRef.current = navigationQueueRef.current.then(async () => {
        try {
          await captureActivePreview()
        } catch (error) {
          console.error(error)
        }
        updateTiers((current) => [
          ...current,
          {
            ...createCanvasCardTier(current.length, {
              width: current[0]?.width ?? 220,
              height: current[0]?.height ?? 140,
            }),
            id,
          },
        ])
        activeTierIdRef.current = id
        setActiveTierId(id)
        setTool("select")
      })
    }, [captureActivePreview, updateTiers])

    const requestClose = useCallback(async () => {
      if (closingRef.current) return
      closingRef.current = true
      await navigationQueueRef.current
      if (!(await flush())) {
        closingRef.current = false
        return
      }
      try {
        await onClose()
      } catch (error) {
        setSaveError(
          error instanceof Error ? error.message : "Couldn’t close the card editor.",
        )
        closingRef.current = false
      }
    }, [flush, onClose])

    useImperativeHandle(ref, () => ({ requestClose }), [requestClose])

    const selectTool = (next: CanvasTool) => {
      if (next === "hand") return
      if (next === "image" || next === "video") {
        setTool("select")
        if (next === "image") canvasRef.current?.insertImage()
        else canvasRef.current?.insertVideo()
        return
      }
      setTool(next)
      const group = groupForTool(next)
      if (group) rememberedRef.current[group] = next
    }

    useEffect(() => {
      const blur = () => void flush()
      const keydown = (event: KeyboardEvent) => {
        if (standalone && event.key === "Escape") {
          event.preventDefault()
          void requestClose()
          return
        }
        if (
          event.repeat ||
          event.metaKey ||
          event.ctrlKey ||
          event.altKey ||
          event.target instanceof HTMLInputElement ||
          event.target instanceof HTMLTextAreaElement ||
          event.target instanceof HTMLSelectElement ||
          (event.target instanceof HTMLElement && event.target.isContentEditable)
        )
          return
        const group = groupForShortcut(event.key, enabledTools)
        if (!group) return
        event.preventDefault()
        setTool((current) =>
          nextToolForGroup(
            group,
            current,
            rememberedRef.current[group],
            enabledTools,
            event.shiftKey ? -1 : 1,
          ),
        )
      }
      window.addEventListener("blur", blur)
      window.addEventListener("keydown", keydown)
      return () => {
        window.removeEventListener("blur", blur)
        window.removeEventListener("keydown", keydown)
        if (timerRef.current !== null) window.clearTimeout(timerRef.current)
        if (resizeTimerRef.current !== null)
          window.clearTimeout(resizeTimerRef.current)
      }
    }, [enabledTools, flush, requestClose, standalone])

    useEffect(() => {
      const stage = stageRef.current
      if (!stage) return undefined
      const resize = () => {
        if (resizeTimerRef.current !== null)
          window.clearTimeout(resizeTimerRef.current)
        resizeTimerRef.current = window.setTimeout(() => {
          resizeTimerRef.current = null
          const bounds = stage.getBoundingClientRect()
          const width = Math.max(1, Math.round(bounds.width))
          const height = Math.max(1, Math.round(bounds.height))
          updateTiers((current) => {
            if (
              current.every(
                (tier) => tier.width === width && tier.height === height,
              )
            )
              return current
            previewCacheRef.current.clear()
            return current.map((tier) => ({
              ...tier,
              width,
              height,
              revision: tier.revision + 1,
            }))
          })
        }, 160)
      }
      const observer = new ResizeObserver(resize)
      observer.observe(stage)
      resize()
      return () => observer.disconnect()
    }, [updateTiers])

    const activeIndex = Math.max(
      0,
      tiers.findIndex((tier) => tier.id === activeTierId),
    )
    const activeTier = tiers[activeIndex] ?? tiers[0]
    const activeState = activeTier ? stateFor(activeTier) : null

    const deleteActiveTier = () => {
      if (!activeTier || activeIndex === 0) return
      navigationQueueRef.current = navigationQueueRef.current.then(() => {
        const currentIndex = tiersRef.current.findIndex(
          (tier) => tier.id === activeTier.id,
        )
        if (currentIndex <= 0) return
        const next = tiersRef.current.filter((tier) => tier.id !== activeTier.id)
        previewCacheRef.current.delete(activeTier.id)
        updateTiers(() => next)
        const nextActive = next[Math.min(currentIndex, next.length - 1)] ?? next[0]
        activeTierIdRef.current = nextActive.id
        setActiveTierId(nextActive.id)
        setTool("select")
      })
    }

    const content = (
      <>
        {saveError && (
          <p className="tiered-card-save-error" role="alert">
            {saveError}
          </p>
        )}
        {activeTier && activeState && (
          <div className="tiered-card-editor-stage" ref={stageRef}>
            <header className="card-tier-header">
              <div className="card-tier-navigation">
                <Button
                  type="button"
                  variant="ghost"
                  size="icon-sm"
                  disabled={activeIndex === 0}
                  aria-label="Previous tier"
                  onClick={() => selectTier(tiers[activeIndex - 1]?.id ?? activeTier.id)}
                >
                  <ChevronLeft />
                </Button>
                <select
                  aria-label="Active tier"
                  value={activeTier.id}
                  onChange={(event) => selectTier(event.currentTarget.value)}
                >
                  {tiers.map((tier, index) => (
                    <option key={tier.id} value={tier.id}>
                      {index + 1}. {tier.name}
                    </option>
                  ))}
                </select>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon-sm"
                  disabled={activeIndex === tiers.length - 1}
                  aria-label="Next tier"
                  onClick={() => selectTier(tiers[activeIndex + 1]?.id ?? activeTier.id)}
                >
                  <ChevronRight />
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon-sm"
                  aria-label="Add tier"
                  onClick={addTier}
                >
                  <Plus />
                </Button>
              </div>
              {activeIndex > 0 && (
                <div className="card-tier-actions">
                  <input
                    aria-label={`Tier ${activeIndex + 1} name`}
                    value={activeTier.name}
                    onChange={(event) => {
                      const name = event.currentTarget.value
                      updateTiers((current) =>
                        current.map((tier) =>
                          tier.id === activeTier.id
                            ? { ...tier, name, revision: tier.revision + 1 }
                            : tier,
                        ),
                      )
                    }}
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    disabled={activeIndex === 1}
                    aria-label="Move tier up"
                    onClick={() =>
                      updateTiers((current) => {
                        const index = current.findIndex(
                          (tier) => tier.id === activeTier.id,
                        )
                        if (index <= 1) return current
                        const next = [...current]
                        ;[next[index - 1], next[index]] = [
                          next[index],
                          next[index - 1],
                        ]
                        return next
                      })
                    }
                  >
                    <ArrowUp />
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    disabled={activeIndex === tiers.length - 1}
                    aria-label="Move tier down"
                    onClick={() =>
                      updateTiers((current) => {
                        const index = current.findIndex(
                          (tier) => tier.id === activeTier.id,
                        )
                        if (index < 1 || index >= current.length - 1) return current
                        const next = [...current]
                        ;[next[index], next[index + 1]] = [
                          next[index + 1],
                          next[index],
                        ]
                        return next
                      })
                    }
                  >
                    <ArrowDown />
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    aria-label="Delete tier"
                    onClick={deleteActiveTier}
                  >
                    <Trash2 />
                  </Button>
                </div>
              )}
            </header>
            {activeIndex === 0 && activeTier.kind !== "canvas" && (
              <p className="card-tier-native-note">
                This Front uses its {activeTier.kind} editor. Added tiers use the canvas
                below.
              </p>
            )}
            <CanvasSurfaceContextMenu canvasRef={canvasRef}>
              <div className="blank-card-editor-canvas">
                <EndlessCanvas
                  key={activeTier.id}
                  ref={canvasRef}
                  tool={
                    activeIndex === 0 && activeTier.kind !== "canvas"
                      ? "select"
                      : tool
                  }
                  initialState={activeState}
                  options={options}
                  style={{ width: "100%", height: "100%" }}
                  onChange={(state) => {
                    updateTiers((current) =>
                      current.map((tier) =>
                        tier.id === activeTier.id
                          ? {
                              ...tier,
                              elements: state.objects,
                              revision: tier.revision + 1,
                            }
                          : tier,
                      ),
                    )
                  }}
                  onToolChangeRequest={selectTool}
                />
                {!(activeIndex === 0 && activeTier.kind !== "canvas") && (
                  <CanvasToolbar
                    tool={tool}
                    onToolChange={selectTool}
                    enabledTools={enabledTools}
                    preferredTools={{ text: "markdown" }}
                    iconOverrides={{ markdown: <MarkdownToolIcon /> }}
                  />
                )}
              </div>
            </CanvasSurfaceContextMenu>
          </div>
        )}
      </>
    )

    if (standalone) {
      return (
        <main className="blank-card-editor-dialog tiered-card-editor-window">
          <h1 className="sr-only">Edit card</h1>
          <p className="sr-only">
            Front appears on the notebook. Later tiers are revealed in Revise.
          </p>
          {content}
        </main>
      )
    }

    return (
      <Dialog open onOpenChange={(open) => !open && void requestClose()}>
        <DialogContent
          className="blank-card-editor-dialog tiered-card-editor-dialog"
          showCloseButton={false}
          onEscapeKeyDown={(event) => {
            event.preventDefault()
            void requestClose()
          }}
          onPointerDownOutside={(event) => {
            event.preventDefault()
            void requestClose()
          }}
        >
          <DialogTitle className="sr-only">Edit card</DialogTitle>
          <DialogDescription className="sr-only">
            Front appears on the notebook. Later tiers are revealed in Revise.
          </DialogDescription>
          {content}
        </DialogContent>
      </Dialog>
    )
  },
)
