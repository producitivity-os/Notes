import {
  Fragment,
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react"
import { ArrowDown, ArrowUp, Plus, Trash2 } from "@productivity-os/shared-ui/components/sf-symbols"
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
    const initialStatesRef = useRef<Map<string, EndlessCanvasState> | null>(null)
    if (initialStatesRef.current === null) {
      initialStatesRef.current = new Map(tiers.map((tier) => [tier.id, stateFor(tier)]))
    }
    const canvasRefs = useRef(new Map<string, EndlessCanvasHandle>())
    const tierSectionRefs = useRef(new Map<string, HTMLElement>())
    const timerRef = useRef<number | null>(null)
    const closingRef = useRef(false)
    const mutationVersionRef = useRef(0)
    const persistedVersionRef = useRef(-1)
    const saveQueueRef = useRef<Promise<boolean>>(Promise.resolve(true))
    const [activeTierId, setActiveTierId] = useState("front")
    const [saveError, setSaveError] = useState<string | null>(null)
    const rememberedRef = useRef<Partial<Record<CanvasToolGroupId, CanvasTool>>>({
      shapes: "rect",
      connector: "arrow",
      text: "markdown",
      image: "image",
    })
    const [tool, setTool] = useState<CanvasTool>("select")
    const enabledTools = toolsForNotebookDepth(1)
    const nativeClipboard = useMemo(createTauriCanvasClipboard, [])
    const options = useMemo<EndlessCanvasOptions>(
      () => ({
        maxPaneDepth: 0,
        assets,
        clipboard: nativeClipboard,
        defaultTextFormat: "markdown",
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
          const next = snapshot()
          const previews = (
            await Promise.all(
              next.map(async (tier) => {
                if (tier.id === "front" && tier.kind !== "canvas") return null
                const dataUrl = await canvasRefs.current.get(tier.id)?.captureSnapshot({
                  format: "jpeg",
                  quality: 0.8,
                  resolution: 0.5,
                })
                return dataUrl
                  ? {
                      tierId: tier.id,
                      tierRevision: tier.revision,
                      dataUrl,
                    }
                  : null
              }),
            )
          ).filter((value) => value !== null)
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
    }, [onSave, snapshot])

    const scheduleSave = useCallback(() => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current)
      timerRef.current = window.setTimeout(() => void flush(), AUTOSAVE_DELAY)
    }, [flush])

    const updateTiers = useCallback(
      (update: (current: CanvasCardTier[]) => CanvasCardTier[]) => {
        const next = update(tiersRef.current)
        mutationVersionRef.current += 1
        tiersRef.current = next
        setTiers(next)
        scheduleSave()
      },
      [scheduleSave],
    )

    const addTier = useCallback(() => {
      const id = crypto.randomUUID()
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
      setActiveTierId(id)
      window.requestAnimationFrame(() =>
        tierSectionRefs.current
          .get(id)
          ?.scrollIntoView({ behavior: "smooth", block: "start" }),
      )
    }, [updateTiers])

    const requestClose = useCallback(async () => {
      if (closingRef.current) return
      closingRef.current = true
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
      const activeCanvas = canvasRefs.current.get(activeTierId)
      if (next === "image" || next === "video") {
        setTool("select")
        if (next === "image") activeCanvas?.insertImage()
        else activeCanvas?.insertVideo()
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
      }
    }, [enabledTools, flush, requestClose, standalone])

    const content = (
      <>
        {saveError && (
          <p className="tiered-card-save-error" role="alert">
            {saveError}
          </p>
        )}
        <div className="tiered-card-editor-scroll">
          {tiers.map((tier, index) => {
            let initialState = initialStatesRef.current!.get(tier.id)
            if (!initialState) {
              initialState = stateFor(tier)
              initialStatesRef.current!.set(tier.id, initialState)
            }
            return (
              <Fragment key={tier.id}>
                <section
                  className="card-tier-section"
                  data-active={tier.id === activeTierId || undefined}
                  data-tier-index={index}
                  ref={(element) => {
                    if (element) tierSectionRefs.current.set(tier.id, element)
                    else tierSectionRefs.current.delete(tier.id)
                  }}
                  onPointerDown={() => setActiveTierId(tier.id)}
                >
                  <header className="card-tier-header">
                    {index === 0 ? (
                      <strong>Front</strong>
                    ) : (
                      <input
                        aria-label={`Tier ${index + 1} name`}
                        value={tier.name}
                        onChange={(event) => {
                          const name = event.currentTarget.value
                          updateTiers((current) =>
                            current.map((item) =>
                              item.id === tier.id
                                ? { ...item, name, revision: item.revision + 1 }
                                : item,
                            ),
                          )
                        }}
                      />
                    )}
                    {index > 0 && (
                      <div className="card-tier-actions">
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon-sm"
                          disabled={index === 1}
                          aria-label="Move tier up"
                          onClick={() =>
                            updateTiers((current) => {
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
                          disabled={index === tiers.length - 1}
                          aria-label="Move tier down"
                          onClick={() =>
                            updateTiers((current) => {
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
                          onClick={() => {
                            canvasRefs.current.delete(tier.id)
                            updateTiers((current) =>
                              current.filter((item) => item.id !== tier.id),
                            )
                            setActiveTierId("front")
                          }}
                        >
                          <Trash2 />
                        </Button>
                      </div>
                    )}
                  </header>
                  {index === 0 && tier.kind !== "canvas" && (
                    <p className="card-tier-native-note">
                      This Front uses its {tier.kind} editor. Added tiers use the canvas
                      below.
                    </p>
                  )}
                  <CanvasSurfaceContextMenu
                    canvasRef={{
                      get current() {
                        return canvasRefs.current.get(tier.id) ?? null
                      },
                    }}
                  >
                    <div className="blank-card-editor-canvas">
                      <EndlessCanvas
                        ref={(handle) => {
                          if (handle) canvasRefs.current.set(tier.id, handle)
                          else canvasRefs.current.delete(tier.id)
                        }}
                        tool={
                          tier.id === activeTierId &&
                          !(index === 0 && tier.kind !== "canvas")
                            ? tool
                            : "select"
                        }
                        initialState={initialState}
                        options={options}
                        style={{ width: "100%", height: "100%" }}
                        onChange={(state) => {
                          updateTiers((current) =>
                            current.map((item) =>
                              item.id === tier.id
                                ? {
                                    ...item,
                                    elements: state.objects,
                                    revision: item.revision + 1,
                                  }
                                : item,
                            ),
                          )
                        }}
                        onToolChangeRequest={selectTool}
                      />
                      {tier.id === activeTierId &&
                        !(index === 0 && tier.kind !== "canvas") && (
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
                </section>
                {index === 0 && (
                  <div className="card-tier-appendage">
                    <Button
                      type="button"
                      variant="outline"
                      className="add-card-tier"
                      onClick={addTier}
                    >
                      <Plus /> Add tier
                    </Button>
                  </div>
                )}
              </Fragment>
            )
          })}
        </div>
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
