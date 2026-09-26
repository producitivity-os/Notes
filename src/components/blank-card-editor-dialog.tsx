import { useEffect, useMemo, useRef, useState } from "react";
import {
  CanvasToolbar,
  CanvasSurfaceContextMenu,
  EndlessCanvas,
  canvasObjectFactory,
  groupForShortcut,
  groupForTool,
  nextToolForGroup,
  type CanvasObject,
  type CanvasTool,
  type CanvasToolGroupId,
  type EndlessCanvasHandle,
  type EndlessCanvasOptions,
  type EndlessCanvasState,
} from "@productivity-os/canvas";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@productivity-os/shared-ui/components/ui/dialog";
import { toolsForNotebookDepth } from "@/canvas/notebook-policy";
import { MarkdownToolIcon } from "@/components/markdown-tool-icon";
import { createTauriCanvasClipboard } from "@/api/tauri-canvas-clipboard";

type Props = {
  mode: "create" | "edit";
  initialElements: readonly CanvasObject[];
  assets: NonNullable<EndlessCanvasOptions["assets"]>;
  onSave(elements: CanvasObject[]): void;
  onCancel(): void;
};

const EDITOR_LAYER = "card-editor";

const cloneElements = (elements: readonly CanvasObject[]) =>
  structuredClone(elements).map((element) =>
    canvasObjectFactory.hydrate({
      ...element,
      layerId: EDITOR_LAYER,
    } as CanvasObject),
  );

export function BlankCardEditorDialog({
  mode,
  initialElements,
  assets,
  onSave,
  onCancel,
}: Props) {
  const stateRef = useRef<EndlessCanvasState | null>(null);
  const canvasRef = useRef<EndlessCanvasHandle>(null);
  const rememberedRef = useRef<Partial<Record<CanvasToolGroupId, CanvasTool>>>({
    shapes: "rect",
    connector: "arrow",
    text: "markdown",
    image: "image",
  });
  const [tool, setTool] = useState<CanvasTool>("select");
  const [initialState] = useState<EndlessCanvasState>(() => ({
    activeLayerId: EDITOR_LAYER,
    focusedLayerId: null,
    unfocusedLayerOpacity: 1,
    viewport: { x: 0, y: 0, scale: 1 },
    layers: [
      {
        id: EDITOR_LAYER,
        name: "Card",
        zIndex: 0,
        visible: true,
        opacity: 1,
        interactionColor: 0x3b82f6,
      },
    ],
    objects: cloneElements(initialElements),
  }));
  stateRef.current ??= initialState;
  const enabledTools = toolsForNotebookDepth(1);
  const nativeClipboard = useMemo(createTauriCanvasClipboard, []);
  const options = useMemo<EndlessCanvasOptions>(
    () => ({
      maxPaneDepth: 0,
      assets,
      clipboard: nativeClipboard,
      defaultTextFormat: "markdown",
      canInsertObject: (object) => object.type !== "card",
    }),
    [assets, nativeClipboard],
  );

  const selectTool = (next: CanvasTool) => {
    if (next === "image" || next === "video") {
      setTool("select");
      if (next === "image") canvasRef.current?.insertImage();
      else canvasRef.current?.insertVideo();
      return;
    }
    setTool(next);
    const group = groupForTool(next);
    if (group) rememberedRef.current[group] = next;
  };

  useEffect(() => {
    const keydown = (event: KeyboardEvent) => {
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
        document.querySelector("[data-slot='dropdown-menu-content']")
      )
        return;
      const group = groupForShortcut(event.key, enabledTools);
      if (!group) return;
      event.preventDefault();
      setTool((current) =>
        nextToolForGroup(
          group,
          current,
          rememberedRef.current[group],
          enabledTools,
          event.shiftKey ? -1 : 1,
        ),
      );
    };
    window.addEventListener("keydown", keydown);
    return () => window.removeEventListener("keydown", keydown);
  }, [enabledTools]);

  return (
    <Dialog open onOpenChange={(open) => !open && onCancel()}>
      <DialogContent
        className="blank-card-editor-dialog"
        showCloseButton={false}
        onEscapeKeyDown={() => onCancel()}
        onKeyDown={(event) => {
          if (event.key !== "Enter" || (!event.metaKey && !event.ctrlKey))
            return;
          event.preventDefault();
          onSave(cloneElements(stateRef.current?.objects ?? []));
        }}
      >
        <DialogHeader className="sr-only">
          <DialogTitle>
            {mode === "create" ? "New blank card" : "Edit blank card"}
          </DialogTitle>
          <DialogDescription>
            Draw the contents of this card, then save it back to the notebook.
          </DialogDescription>
        </DialogHeader>
        <CanvasSurfaceContextMenu canvasRef={canvasRef}>
          <div className="blank-card-editor-canvas">
            <EndlessCanvas
              ref={canvasRef}
              tool={tool}
              initialState={initialState}
              options={options}
              style={{ width: "100%", height: "100%" }}
              onChange={(state) => {
                stateRef.current = state;
              }}
              onToolChangeRequest={selectTool}
            />
            <CanvasToolbar
              tool={tool}
              onToolChange={selectTool}
              enabledTools={enabledTools}
              preferredTools={{ text: "markdown" }}
              iconOverrides={{ markdown: <MarkdownToolIcon /> }}
            />
          </div>
        </CanvasSurfaceContextMenu>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>
            Cancel <kbd>Esc</kbd>
          </Button>
          <Button
            type="button"
            onClick={() =>
              onSave(cloneElements(stateRef.current?.objects ?? []))
            }
          >
            Save <kbd>⌘↵</kbd>
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
