import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  Braces,
  CircleHelp,
  RefreshCw,
  Save,
  Square,
  X,
} from "lucide-react";
import { IconGlyph } from "@productivity-os/shared-ui/components/icon-select";
import { WorkspaceDocumentHeader } from "@productivity-os/shared-ui/components/app-header";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import { Progress } from "@productivity-os/shared-ui/components/ui/progress";
import {
  EndlessCanvas,
  CanvasMinimap,
  CanvasSurfaceContextMenu,
  CanvasToolbar,
  CanvasToolbarCustomMenuTool,
  ImageObject,
  IllustrationCard,
  MarkdownCard,
  canvasObjectFactory,
  expandCardToContent,
  groupForShortcut,
  groupForTool,
  minCardHeight,
  minCardWidth,
  nextCustomMenuItem,
  nextToolForGroup,
  type CanvasCardObject,
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
} from "@productivity-os/canvas";
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
} from "@/api/notebook-data";
import { NotebookPanel } from "@/components/notebook-panel";
import { DiscreteProperties } from "@/components/discrete-properties";
import { BlankCardEditorDialog } from "@/components/blank-card-editor-dialog";
import { MarkdownToolIcon } from "@/components/markdown-tool-icon";
import { CardEditorDialog } from "@/components/card-editor-dialog";
import type { CardPluginDefinition } from "@/plugins/plugin-api";
import { notesPlugins } from "@/plugins/plugin-registry";
import {
  applyNotebookRootArrowStyle,
  allowsNotebookInsertion,
  migrateNotebookRootArrows,
  migrateLegacyNotebookTextStyles,
  toolsForNotebookDepth,
} from "@/canvas/notebook-policy";
import {
  importNotebookImage,
  notebookMediaData,
  notebookMediaUrl,
} from "@/api/notebook-media";
import { createTauriCanvasClipboard } from "@/api/tauri-canvas-clipboard";

type SaveState = "saved" | "saving" | "unsaved" | "error";
type NotebookLoadState = {
  progress: number;
  label: string;
  error: string | null;
  visible: boolean;
};

type CardEditorState =
  | {
      kind: "blank";
      mode: "create" | "edit";
      point?: CanvasPoint;
      bounds?: { x: number; y: number; width: number; height: number };
      cardId?: string;
      elements: CanvasObject[];
    }
  | {
      kind: "plugin";
      mode: "create" | "edit";
      plugin: CardPluginDefinition<any, any>;
      point?: CanvasPoint;
      cardId?: string;
      initialData: unknown;
    };

type InlinePluginEditorState = {
  cardId: string;
  regionId: string;
};

function PluginInlineEditorOverlay({
  overlay,
  plugin,
  regionId,
  onRegionChange,
  onClose,
}: {
  overlay: CanvasObjectOverlaySlotProps;
  plugin: CardPluginDefinition<any, any>;
  regionId: string;
  onRegionChange(regionId: string): void;
  onClose(): void;
}) {
  const transactionActive = useRef(false);
  const latestOverlay = useRef(overlay);
  latestOverlay.current = overlay;
  const card = overlay.object as PluginCard;
  const adapter = plugin.slots.InlineEditor;

  useEffect(() => {
    latestOverlay.current.beginMutation();
    transactionActive.current = true;
    return () => {
      if (transactionActive.current) latestOverlay.current.commitMutation();
      transactionActive.current = false;
    };
  }, [card.id]);

  if (!adapter) return null;
  const Editor = adapter.Component;
  return (
    <Editor
      card={card}
      data={plugin.hydrate(card.pluginData)}
      regionId={regionId}
      scale={overlay.viewport.scale}
      onChange={(data, height) =>
        overlay.update({
          pluginData: plugin.serialize(data),
          pluginVersion: plugin.manifest.card.schemaVersion,
          height: Math.max(card.height, height),
        } as Partial<PluginCard>)
      }
      onRegionChange={onRegionChange}
      onCancel={() => {
        transactionActive.current = false;
        overlay.cancelMutation();
        onClose();
      }}
    />
  );
}

function pickFile(
  accept: string,
  video = false,
): Promise<{
  dataUrl?: string;
  src?: string;
  name: string;
  width: number;
  height: number;
} | null> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) return resolve(null);
      const reader = new FileReader();
      reader.onload = () => {
        const source = String(reader.result);
        const media = document.createElement(video ? "video" : "img");
        media.onloadedmetadata = media.onload = () =>
          resolve({
            ...(video ? { src: source } : { dataUrl: source }),
            name: file.name,
            width: video
              ? (media as HTMLVideoElement).videoWidth
              : (media as HTMLImageElement).naturalWidth,
            height: video
              ? (media as HTMLVideoElement).videoHeight
              : (media as HTMLImageElement).naturalHeight,
          });
        media.onerror = () => resolve(null);
        media.src = source;
      };
      reader.readAsDataURL(file);
    };
    input.click();
  });
}

export function NotebookDetail({ notebookId }: { notebookId: string }) {
  const canvasRef = useRef<EndlessCanvasHandle>(null);
  const notebookRef = useRef<NotebookDocument | null>(null);
  const canvasStateRef = useRef<EndlessCanvasState | null>(null);
  const saveTimerRef = useRef<number | null>(null);
  const saveInFlightRef = useRef<Promise<void> | null>(null);
  const saveQueuedRef = useRef(false);
  const pendingCardRef = useRef<{
    cardId: string;
    data?: Record<string, unknown>;
  }>({ cardId: "blank" });
  const activeLayerRef = useRef("main");
  const paneDepthRef = useRef(0);
  const rememberedToolsRef = useRef<
    Partial<Record<CanvasToolGroupId, CanvasTool>>
  >({ shapes: "rect", connector: "arrow", text: "text", image: "image" });
  const allowCloseRef = useRef(false);
  const [notebook, setNotebook] = useState<NotebookDocument | null>(null);
  const [notebooks, setNotebooks] = useState<NotebookSummary[]>([]);
  const [canvasState, setCanvasState] = useState<EndlessCanvasState | null>(
    null,
  );
  const [tool, setTool] = useState<CanvasTool>("select");
  const [pane, setPane] = useState<CanvasPaneContext>({
    stackLevel: 0,
    cardPath: [],
    canGoBack: false,
    maxPaneDepth: 1,
  });
  const [panelOpen, setPanelOpen] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>("saved");
  const [zoom, setZoom] = useState(1);
  const [rememberedCardId, setRememberedCardId] = useState("blank");
  const [rememberedQuestionKind, setRememberedQuestionKind] = useState<
    "basic" | "cloze"
  >("basic");
  const [activeCardId, setActiveCardId] = useState<string | null>(null);
  const [inlinePluginEditor, setInlinePluginEditor] =
    useState<InlinePluginEditorState | null>(null);
  const [cardEditor, setCardEditor] = useState<CardEditorState | null>(null);
  const [pluginRevision, setPluginRevision] = useState(0);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [loadState, setLoadState] = useState<NotebookLoadState>({
    progress: 6,
    label: "Opening notebook…",
    error: null,
    visible: true,
  });

  const closeWindow = useCallback(() => {
    if (!isTauri) {
      window.close();
      return;
    }
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) => getCurrentWindow().close())
      .catch(() => window.close());
  }, []);

  const saveNow = useCallback(async function flushNotebook(): Promise<void> {
    if (saveInFlightRef.current) {
      saveQueuedRef.current = true;
      await saveInFlightRef.current;
      return;
    }
    const current = notebookRef.current;
    const state = canvasStateRef.current;
    if (!current || !state) return;
    if (saveTimerRef.current !== null)
      window.clearTimeout(saveTimerRef.current);
    saveTimerRef.current = null;
    setSaveState("saving");
    const operation = (async () => {
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
        });
        let previewDataUrl = summary.previewDataUrl;
        try {
          previewDataUrl =
            (await canvasRef.current?.captureSnapshot({
              format: "jpeg",
              quality: 0.72,
              resolution: 0.35,
            })) ?? previewDataUrl;
          if (previewDataUrl)
            await notebookData.savePreview(current.id, previewDataUrl);
        } catch {
          // Saving notebook content is authoritative; a preview may be regenerated later.
        }
        const next = { ...current, ...summary, previewDataUrl };
        notebookRef.current = next;
        setNotebook(next);
        setSaveState("saved");
      } catch (error) {
        console.error(error);
        setSaveState("error");
      }
    })();
    saveInFlightRef.current = operation;
    await operation;
    saveInFlightRef.current = null;
    if (saveQueuedRef.current) {
      saveQueuedRef.current = false;
      await flushNotebook();
    }
  }, []);

  const scheduleSave = useCallback(
    (state: EndlessCanvasState) => {
      canvasStateRef.current = state;
      setSaveState("unsaved");
      if (saveTimerRef.current !== null)
        window.clearTimeout(saveTimerRef.current);
      saveTimerRef.current = window.setTimeout(() => void saveNow(), 650);
    },
    [saveNow],
  );

  const refreshPlugins = useCallback(async () => {
    const installations = await pluginData.list();
    notesPlugins.setInstallations(
      installations
        .filter((item) => item.installed)
        .map((item) => item.pluginId),
    );
    setPluginRevision((value) => value + 1);
  }, []);

  useEffect(() => {
    let cancelled = false;
    let completedFetches = 0;
    setNotebook(null);
    setCanvasState(null);
    notebookRef.current = null;
    canvasStateRef.current = null;
    setLoadState({
      progress: 6,
      label: "Opening notebook…",
      error: null,
      visible: true,
    });
    const track = async <T,>(
      promise: Promise<T>,
      label: string,
    ): Promise<T> => {
      const value = await promise;
      completedFetches += 1;
      if (!cancelled) {
        const progress = 12 + completedFetches * 18;
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, progress),
          label,
        }));
      }
      return value;
    };
    void Promise.all([
      track(notebookData.get(notebookId), "Notebook loaded"),
      track(notebookData.list(), "Notebook index loaded"),
      track(pluginData.list(), "Card plugins loaded"),
      track(personData.list(), "People loaded"),
    ])
      .then(([stored, all, installations, people]) => {
        if (cancelled) return;
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, 76),
          label: "Preparing cards…",
        }));
        notesPlugins.setInstallations(
          installations
            .filter((item) => item.installed)
            .map((item) => item.pluginId),
        );
        notesPlugins.setPersons(people);
        setPluginRevision((value) => value + 1);
        const migratedRootArrows = stored
          ? migrateNotebookRootArrows(stored.canvas)
          : false;
        const initialState = stored
          ? snapshotToCanvas(stored.canvas)
          : createEmptyNotebookState();
        const migratedCards = notesPlugins.migrateCards(initialState.objects);
        const migratedTextStyles = migrateLegacyNotebookTextStyles(
          initialState.objects,
        );
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
        };
        notebookRef.current = document;
        canvasStateRef.current = initialState;
        activeLayerRef.current = initialState.activeLayerId ?? "main";
        setZoom(initialState.viewport?.scale ?? 1);
        setNotebook(document);
        setNotebooks(all);
        setCanvasState(initialState);
        setLoadState((current) => ({
          ...current,
          progress: Math.max(current.progress, 92),
          label: "Starting canvas…",
        }));
        if (migratedCards || migratedRootArrows || migratedTextStyles)
          scheduleSave(initialState);
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        setLoadState((current) => ({
          ...current,
          error: error instanceof Error ? error.message : String(error),
          label: "Couldn’t open this notebook",
          visible: true,
        }));
      });
    return () => {
      cancelled = true;
    };
  }, [loadAttempt, notebookId, scheduleSave]);

  const handleCanvasReady = useCallback(() => {
    setLoadState((current) => ({
      ...current,
      progress: 100,
      label: "Notebook ready",
      error: null,
      visible: true,
    }));
    window.setTimeout(
      () => setLoadState((current) => ({ ...current, visible: false })),
      180,
    );
  }, []);

  useEffect(() => {
    const initialFocus = new URLSearchParams(window.location.search).get(
      "focus",
    );
    let unlisten: (() => void) | undefined;
    const focus = (objectId: string | null) => {
      if (objectId)
        window.requestAnimationFrame(() =>
          canvasRef.current?.focusObject(objectId),
        );
    };
    focus(initialFocus);
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen<string>("notes:focus-object", (event) => focus(event.payload)),
      )
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => unlisten?.();
  }, [canvasState]);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    const refresh = () => void refreshPlugins();
    window.addEventListener("notes:plugins-changed", refresh);
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:plugins-changed", refresh))
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => {
      unlisten?.();
      window.removeEventListener("notes:plugins-changed", refresh);
    };
  }, [refreshPlugins]);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    const refresh = () => {
      void personData.list().then((people) => {
        notesPlugins.setPersons(people);
        setPluginRevision((value) => value + 1);
      });
    };
    window.addEventListener("notes:persons-changed", refresh);
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:persons-changed", refresh))
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => {
      unlisten?.();
      window.removeEventListener("notes:persons-changed", refresh);
    };
  }, []);

  useEffect(() => {
    if (!isTauri) return undefined;
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) =>
        getCurrentWindow().onCloseRequested(async (event) => {
          if (allowCloseRef.current) return;
          event.preventDefault();
          await saveNow();
          allowCloseRef.current = true;
          await getCurrentWindow().destroy();
        }),
      )
      .then((dispose) => {
        unlisten = dispose;
      });
    return () => unlisten?.();
  }, [saveNow]);

  useEffect(
    () => () => {
      if (saveTimerRef.current !== null)
        window.clearTimeout(saveTimerRef.current);
      notesPlugins.dispose();
    },
    [],
  );

  const handlePaneChange = useCallback((context: CanvasPaneContext) => {
    paneDepthRef.current = context.stackLevel;
    setPane(context);
    setTool("select");
  }, []);
  const handleLayersChange = useCallback((api: { activeLayerId: string }) => {
    activeLayerRef.current = api.activeLayerId;
  }, []);
  const handleViewportChange = useCallback(
    (viewport: EndlessCanvasState["viewport"]) => {
      setZoom(viewport?.scale ?? 1);
    },
    [],
  );
  const selectTool = useCallback((nextTool: CanvasTool) => {
    setActiveCardId(null);
    if (nextTool === "image" || nextTool === "video") {
      setTool("select");
      if (nextTool === "image") canvasRef.current?.insertImage();
      else canvasRef.current?.insertVideo();
      return;
    }
    setTool(nextTool);
    const group = groupForTool(nextTool);
    if (group) rememberedToolsRef.current[group] = nextTool;
  }, []);
  const handleToolChangeRequest = selectTool;

  const armCard = useCallback(
    (cardId: string, data?: Record<string, unknown>) => {
      setRememberedCardId(cardId);
      pendingCardRef.current = { cardId, data };
      setActiveCardId(cardId);
      setTool("add");
    },
    [],
  );

  const enabledTools = toolsForNotebookDepth(pane.stackLevel);
  const pluginCards = useMemo(() => {
    void pluginRevision;
    return notesPlugins.availableCards();
  }, [pluginRevision]);
  const questionPlugin = useMemo(
    () =>
      pluginCards.find((card) => card.manifest.id === "notes.question-card") ??
      null,
    [pluginCards],
  );
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
      ...pluginCards
        .filter((card) => card.manifest.id !== "notes.question-card")
        .map((card) => {
          const ToolbarIcon = card.slots.ToolbarIcon;
          return {
            id: card.manifest.id,
            label: card.manifest.name,
            icon: <ToolbarIcon />,
            selected: rememberedCardId === card.manifest.id,
            onSelect: () => armCard(card.manifest.id),
          };
        }),
    ],
    [armCard, pluginCards, rememberedCardId],
  );

  const armQuestion = useCallback(
    (kind: "basic" | "cloze") => {
      if (!questionPlugin) return;
      setRememberedQuestionKind(kind);
      pendingCardRef.current = {
        cardId: questionPlugin.manifest.id,
        data: { revisionKind: kind },
      };
      setActiveCardId(questionPlugin.manifest.id);
      setTool("add");
    },
    [questionPlugin],
  );
  const questionItems = useMemo(
    () => [
      {
        id: "basic",
        label: "Basic question",
        icon: <CircleHelp />,
        selected: rememberedQuestionKind === "basic",
        onSelect: () => armQuestion("basic"),
      },
      {
        id: "cloze",
        label: "Cloze question",
        icon: <Braces />,
        selected: rememberedQuestionKind === "cloze",
        onSelect: () => armQuestion("cloze"),
      },
    ],
    [armQuestion, rememberedQuestionKind],
  );

  useEffect(() => {
    if (cardItems.some((item) => item.id === rememberedCardId)) return;
    setRememberedCardId("blank");
    pendingCardRef.current = { cardId: "blank" };
    setActiveCardId(null);
    if (tool === "add") setTool("select");
  }, [cardItems, rememberedCardId, tool]);

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
        (event.target instanceof HTMLElement &&
          event.target.isContentEditable) ||
        document.querySelector(
          "[data-slot='dialog-content'], [data-slot='dropdown-menu-content']",
        )
      )
        return;
      if (event.key.toLowerCase() === "c" && paneDepthRef.current === 0) {
        const next = nextCustomMenuItem(
          cardItems,
          tool === "add" || tool === "markdown-card" ? activeCardId : null,
          rememberedCardId,
          event.shiftKey ? -1 : 1,
        );
        if (next) {
          event.preventDefault();
          next.onSelect();
        }
        return;
      }
      if (
        event.key.toLowerCase() === "q" &&
        paneDepthRef.current === 0 &&
        questionPlugin
      ) {
        const next = nextCustomMenuItem(
          questionItems,
          tool === "add" && activeCardId === questionPlugin.manifest.id
            ? rememberedQuestionKind
            : null,
          rememberedQuestionKind,
          event.shiftKey ? -1 : 1,
        );
        if (next) {
          event.preventDefault();
          next.onSelect();
        }
        return;
      }
      const group = groupForShortcut(event.key, enabledTools);
      if (!group) return;
      event.preventDefault();
      selectTool(
        nextToolForGroup(
          group,
          tool,
          rememberedToolsRef.current[group],
          enabledTools,
          event.shiftKey ? -1 : 1,
        ),
      );
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [
    activeCardId,
    cardItems,
    enabledTools,
    rememberedCardId,
    rememberedQuestionKind,
    selectTool,
    questionItems,
    questionPlugin,
    tool,
  ]);

  const placeCard = useCallback(
    (
      point: CanvasPoint,
      bounds?: { x: number; y: number; width: number; height: number },
    ): CanvasObject | null => {
      const pending = pendingCardRef.current;
      if (!pending || paneDepthRef.current !== 0) return null;
      setTool("select");
      setActiveCardId(null);
      if (pending.cardId === "blank") {
        setCardEditor({
          kind: "blank",
          mode: "create",
          point,
          bounds,
          elements: [],
        });
        return null;
      }
      if (pending.cardId === "markdown") {
        const width = bounds ? Math.max(80, bounds.width) : 220;
        const height = bounds ? Math.max(60, bounds.height) : 140;
        return new MarkdownCard({
          id: crypto.randomUUID(),
          layerId: activeLayerRef.current,
          type: "card",
          kind: "markdown",
          x: bounds?.x ?? point.x - width / 2,
          y: bounds?.y ?? point.y - height / 2,
          width,
          height,
          elements: [],
          markdown: "",
          backgroundColor: 0xffffff,
        });
      }
      const plugin = notesPlugins.definition(pending.cardId);
      if (!plugin || !notesPlugins.isInstalled(pending.cardId)) return null;
      const card = plugin.create({
        notebookId,
        layerId: activeLayerRef.current,
        point,
      });
      if (pending.data)
        card.pluginData = { ...card.pluginData, ...pending.data };
      plugin.normalizeCard?.(card);
      pendingCardRef.current = { cardId: pending.cardId };
      if (plugin.slots.Editor) {
        setCardEditor({
          kind: "plugin",
          mode: "create",
          plugin,
          point,
          initialData: card.pluginData,
        });
        return null;
      }
      return card;
    },
    [notebookId],
  );

  const placeDrawnCard = useCallback(
    (placement: CanvasDrawnPlacement) =>
      placeCard(
        placement.center,
        placement.dragged ? placement.bounds : undefined,
      ),
    [placeCard],
  );

  const resolveArrowDefaults = useCallback(
    (arrowTool: "arrow" | "line", context: CanvasPaneContext) =>
      context.stackLevel === 0 && arrowTool === "arrow"
        ? { stroke: 0x7c3aed, strokeWidth: 4 }
        : undefined,
    [],
  );

  const canvasAssets = useMemo<NonNullable<EndlessCanvasOptions["assets"]>>(
    () => ({
      pickImage: async () => {
        const picked = await pickFile("image/*");
        return picked?.dataUrl
          ? {
              dataUrl: picked.dataUrl,
              name: picked.name,
              width: picked.width,
              height: picked.height,
            }
          : null;
      },
      pickVideo: async () => {
        const picked = await pickFile("video/*", true);
        return picked?.src
          ? {
              src: picked.src,
              name: picked.name,
              width: picked.width,
              height: picked.height,
            }
          : null;
      },
    }),
    [],
  );
  const pluginServices = useMemo(
    () => notesPlugins.hostServices(notebookId),
    [notebookId],
  );
  const nativeClipboard = useMemo(createTauriCanvasClipboard, []);

  const pluginCardExtension = useMemo<CanvasObjectExtension<PluginCard>>(
    () => ({
      type: "card",
      hydrate: (object) => object as PluginCard,
      selectionGeometry: (card) => {
        if (card.kind !== "plugin") return null;
        const adapter = notesPlugins.definition(card.pluginId)?.slots
          .InlineEditor;
        return adapter?.suppressCardSelection ? { shape: "none" } : null;
      },
      minimumSize: (card) => {
        if (card.kind !== "plugin") return null;
        const plugin = notesPlugins.definition(card.pluginId);
        if (!plugin?.slots.InlineEditor) return null;
        return {
          width: plugin.manifest.card.defaultDimensions.width,
          height: plugin.manifest.card.defaultDimensions.height,
        };
      },
      pointerInteractionRegions: (card) => {
        if (card.kind !== "plugin") return [];
        return (
          notesPlugins
            .definition(card.pluginId)
            ?.slots.InlineEditor?.regions(card) ?? []
        );
      },
    }),
    [],
  );

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
      });
      const sourceWidth = media.width ?? input.width;
      const sourceHeight = media.height ?? input.height;
      const scale = Math.min(1, 320 / Math.max(sourceWidth, sourceHeight));
      const imageWidth = sourceWidth * scale;
      const imageHeight = sourceHeight * scale;
      const padding = 12;
      const cardWidth = Math.max(minCardWidth, imageWidth + padding * 2);
      const cardHeight = Math.max(minCardHeight, imageHeight + padding * 2);
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
      });
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
      });
    },
    [notebookId],
  );

  const options = useMemo<EndlessCanvasOptions>(
    () => ({
      maxPaneDepth: 1,
      pluginCards: notesPlugins,
      objectExtensions: [pluginCardExtension],
      objectCapabilities: { card: { rotatable: false } },
      onAddToolDraw: placeDrawnCard,
      resolveArrowDefaults,
      canInsertObject: allowsNotebookInsertion,
      shouldEnterCardPane: () => false,
      clipboard: nativeClipboard,
      onExternalImagePaste: createPastedImageCard,
      onObjectCreate: (object, context) => {
        applyNotebookRootArrowStyle(object, context);
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin")
          return;
        const card = object as PluginCard;
        const definition = notesPlugins.definition(card.pluginId);
        void definition?.lifecycle.onCreate?.({ notebookId, cardId: card.id });
        const inline = definition?.slots.InlineEditor;
        if (inline) {
          window.requestAnimationFrame(() =>
            setInlinePluginEditor({
              cardId: card.id,
              regionId: inline.initialRegion(card),
            }),
          );
        }
      },
      onObjectDelete: (object) => {
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin")
          return;
        const card = object as PluginCard;
        void notesPlugins
          .definition(card.pluginId)
          ?.lifecycle.onDelete?.({ notebookId, cardId: card.id });
      },
      onObjectClick: (object, context) => {
        if (object.type !== "card" || (object as PluginCard).kind !== "plugin")
          return;
        const card = object as PluginCard;
        const inline = notesPlugins.definition(card.pluginId)?.slots
          .InlineEditor;
        if (!inline) return;
        setInlinePluginEditor({
          cardId: card.id,
          regionId: context.regionId ?? inline.initialRegion(card),
        });
      },
      onSelectionChange: (selection) => {
        setInlinePluginEditor((current) =>
          current && selection.selectedIds.includes(current.cardId)
            ? current
            : null,
        );
      },
      onObjectActivate: (object) => {
        if (object.type !== "card") return;
        const genericCard = object as CanvasCardObject;
        if (genericCard.kind === "canvas") {
          setCardEditor({
            kind: "blank",
            mode: "edit",
            cardId: genericCard.id,
            elements: structuredClone(genericCard.elements).map((element) =>
              canvasObjectFactory.hydrate(element),
            ),
          });
          return;
        }
        if (genericCard.kind !== "plugin") return;
        const card = object as PluginCard;
        const definition = notesPlugins.definition(card.pluginId);
        if (definition?.slots.InlineEditor) {
          setInlinePluginEditor({
            cardId: card.id,
            regionId: definition.slots.InlineEditor.initialRegion(card),
          });
          return;
        }
        if (card.pluginId === "notes.notebook-card") {
          const target = String(card.pluginData.targetNotebookId ?? "");
          const title = String(
            card.pluginData.targetNotebookTitle ?? "Notebook",
          );
          if (target) void notebookData.open(target, title);
          void definition?.lifecycle.onActivate?.({
            notebookId,
            cardId: card.id,
          });
          return;
        }
        if (
          definition?.slots.Editor &&
          notesPlugins.isInstalled(card.pluginId)
        ) {
          setCardEditor({
            kind: "plugin",
            mode: "edit",
            plugin: definition,
            cardId: card.id,
            initialData: card.pluginData,
          });
        }
        void definition?.lifecycle.onActivate?.({
          notebookId,
          cardId: card.id,
        });
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
    ],
  );

  const toggleFavorite = useCallback(() => {
    const current = notebookRef.current;
    if (!current) return;
    const next = { ...current, starred: !current.starred };
    notebookRef.current = next;
    setNotebook(next);
    if (canvasStateRef.current) scheduleSave(canvasStateRef.current);
  }, [scheduleSave]);

  const exportNotebook = useCallback(() => {
    const current = notebookRef.current;
    const state = canvasStateRef.current;
    if (!current || !state) return;
    const blob = new Blob(
      [
        JSON.stringify(
          { ...current, canvas: canvasToSnapshot(state) },
          null,
          2,
        ),
      ],
      { type: "application/json" },
    );
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `${current.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase() || "notebook"}.notes.json`;
    link.click();
    URL.revokeObjectURL(link.href);
  }, []);

  useEffect(() => {
    if (!isTauri) return undefined;
    let dispose: (() => void)[] = [];
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
        dispose = listeners;
      })
      .catch(console.error);
    return () => dispose.forEach((listener) => listener());
  }, [exportNotebook, toggleFavorite]);

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
    );
  }

  if (!notebook || !canvasState) {
    return (
      <main className="detail-loading" aria-busy="true" aria-live="polite">
        <div className="detail-loading-card">
          <Progress value={loadState.progress} aria-label={loadState.label} />
        </div>
      </main>
    );
  }

  const setMetadata = (
    patch: Partial<
      Pick<NotebookDocument, "title" | "project" | "icon" | "coverMediaId">
    >,
  ) => {
    const next = { ...notebookRef.current!, ...patch };
    notebookRef.current = next;
    setNotebook(next);
    if (canvasStateRef.current) scheduleSave(canvasStateRef.current);
  };
  const saveBlankCard = (elements: CanvasObject[]) => {
    if (!cardEditor || cardEditor.kind !== "blank") return;
    const existing = cardEditor.cardId
      ? (canvasStateRef.current?.objects.find(
          (object) => object.id === cardEditor.cardId && object.type === "card",
        ) as CanvasCardObject | undefined)
      : undefined;
    const layerId = existing?.layerId ?? activeLayerRef.current;
    const normalizedElements = structuredClone(elements).map((element) =>
      canvasObjectFactory.hydrate({ ...element, layerId } as CanvasObject),
    );
    if (cardEditor.mode === "create") {
      const point = cardEditor.point ?? { x: 0, y: 0 };
      const width = cardEditor.bounds
        ? Math.max(80, cardEditor.bounds.width)
        : 220;
      const height = cardEditor.bounds
        ? Math.max(60, cardEditor.bounds.height)
        : 140;
      const card = new IllustrationCard({
        id: crypto.randomUUID(),
        layerId,
        type: "card",
        kind: "canvas",
        x: cardEditor.bounds?.x ?? point.x - width / 2,
        y: cardEditor.bounds?.y ?? point.y - height / 2,
        width,
        height,
        elements: normalizedElements,
        backgroundColor: 0xffffff,
      });
      if (normalizedElements.length > 0) expandCardToContent(card);
      canvasRef.current?.insertObject(card);
    } else if (existing) {
      const fitted = new IllustrationCard({
        ...structuredClone(existing),
        elements: normalizedElements,
      });
      if (normalizedElements.length > 0) expandCardToContent(fitted);
      canvasRef.current?.updateObject(existing.id, {
        x: fitted.x,
        y: fitted.y,
        width: fitted.width,
        height: fitted.height,
        elements: fitted.elements,
      } as Partial<CanvasCardObject>);
    }
    setCardEditor(null);
  };
  const savePluginCard = (data: Record<string, unknown>) => {
    if (!cardEditor || cardEditor.kind !== "plugin") return;
    if (cardEditor.mode === "create") {
      const card = cardEditor.plugin.create({
        notebookId,
        layerId: activeLayerRef.current,
        point: cardEditor.point ?? { x: 0, y: 0 },
      });
      card.pluginData = data;
      card.pluginVersion = cardEditor.plugin.manifest.card.schemaVersion;
      canvasRef.current?.insertObject(card);
    } else if (cardEditor.cardId) {
      canvasRef.current?.updateObject(cardEditor.cardId, {
        pluginData: data,
        pluginVersion: cardEditor.plugin.manifest.card.schemaVersion,
      } as Partial<PluginCard>);
    }
    setCardEditor(null);
  };
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
      : undefined;
  const questionMenu =
    pane.stackLevel === 0 && questionPlugin
      ? {
          label: "Question",
          icon: <CircleHelp />,
          shortcut: "q",
          active: tool === "add" && activeCardId === questionPlugin.manifest.id,
          onPrimarySelect: () => armQuestion(rememberedQuestionKind),
          items: questionItems,
        }
      : null;

  return (
    <div className="detail-shell">
      <WorkspaceDocumentHeader
        className="detail-document-header absolute inset-x-0 top-0"
        icon={<IconGlyph name={notebook.icon || "file-text"} />}
        title={notebook.title}
        statusTone={saveState === "error" ? "error" : "muted"}
        status={
          saveState === "saved" ? (
            <>
              <Save /> Saved
            </>
          ) : (
            saveState
          )
        }
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
            onChange={scheduleSave}
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
              />
            )}
            propertiesSlot={(props) => {
              const object =
                props.selection.selectedObjects.length === 1
                  ? props.selection.selectedObjects[0]
                  : null;
              const card =
                object?.type === "card" &&
                (object as PluginCard).kind === "plugin"
                  ? (object as PluginCard)
                  : null;
              const plugin = card
                ? notesPlugins.definition(card.pluginId)
                : null;
              return (
                <DiscreteProperties
                  {...props}
                  plugin={plugin}
                  pluginInstalled={
                    card ? notesPlugins.isInstalled(card.pluginId) : false
                  }
                  notebooks={notebooks}
                />
              );
            }}
            objectOverlaySlot={(overlay) => {
              if (
                !inlinePluginEditor ||
                overlay.object.id !== inlinePluginEditor.cardId ||
                overlay.object.type !== "card" ||
                (overlay.object as PluginCard).kind !== "plugin"
              )
                return null;
              const card = overlay.object as PluginCard;
              const plugin = notesPlugins.definition(card.pluginId);
              if (!plugin?.slots.InlineEditor) return null;
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
              );
            }}
          />
        </div>
      </CanvasSurfaceContextMenu>
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
        customTools={
          questionMenu ? (
            <CanvasToolbarCustomMenuTool {...questionMenu} />
          ) : null
        }
        iconOverrides={{
          markdown: <MarkdownToolIcon />,
          "markdown-card": <MarkdownToolIcon />,
        }}
      />
      {cardEditor?.kind === "blank" && (
        <BlankCardEditorDialog
          key={`${cardEditor.mode}-${cardEditor.cardId ?? "new"}`}
          mode={cardEditor.mode}
          initialElements={cardEditor.elements}
          assets={canvasAssets}
          onSave={saveBlankCard}
          onCancel={() => setCardEditor(null)}
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
      {pane.stackLevel === 0 &&
        !panelOpen &&
        !loadState.visible &&
        !cardEditor && (
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
  );
}
