import type {
  CanvasObject,
  CanvasPaneContext,
  CanvasTool,
} from "@productivity-os/canvas";

export const ROOT_NOTEBOOK_TOOLS: readonly CanvasTool[] = [
  "select",
  "hand",
  "card",
  "markdown-card",
  "add",
  "arrow",
  "line",
];
export const CARD_PANE_TOOLS: readonly CanvasTool[] = [
  "select",
  "hand",
  "text",
  "markdown",
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
];

export function toolsForNotebookDepth(depth: number): readonly CanvasTool[] {
  return depth === 0 ? ROOT_NOTEBOOK_TOOLS : CARD_PANE_TOOLS;
}

export function allowsNotebookInsertion(
  object: Pick<CanvasObject, "type">,
  pane: Pick<CanvasPaneContext, "stackLevel">,
): boolean {
  return pane.stackLevel === 0
    ? object.type === "card" || object.type === "arrow"
    : object.type !== "card";
}

type NotebookSnapshotForMigration = {
  schemaVersion: number;
  objects: Array<{
    objectType: string;
    payload: Record<string, unknown>;
  }>;
};

type NotebookArrowForStyling = {
  type: string;
  renderMode?: unknown;
  stroke?: unknown;
  strokeWidth?: unknown;
};

const isLegacyNotebookArrowStyle = (arrow: NotebookArrowForStyling) =>
  (arrow.stroke === undefined || arrow.stroke === 0x334155) &&
  (arrow.strokeWidth === undefined ||
    arrow.strokeWidth === 2 ||
    arrow.strokeWidth === 2.5);

export function applyNotebookRootArrowStyle(
  object: NotebookArrowForStyling,
  pane: Pick<CanvasPaneContext, "stackLevel">,
): boolean {
  if (
    pane.stackLevel !== 0 ||
    object.type !== "arrow" ||
    (object.renderMode !== undefined && object.renderMode !== "between") ||
    !isLegacyNotebookArrowStyle(object)
  ) {
    return false;
  }
  object.stroke = 0x7c3aed;
  object.strokeWidth = 4;
  return true;
}

export function migrateNotebookRootArrows(
  snapshot: NotebookSnapshotForMigration,
): boolean {
  if (snapshot.schemaVersion >= 5) return false;
  for (const object of snapshot.objects) {
    if (object.objectType === "arrow") {
      applyNotebookRootArrowStyle(object.payload as NotebookArrowForStyling, {
        stackLevel: 0,
      });
    }
  }
  snapshot.schemaVersion = 5;
  return true;
}

type LegacyTextStyleObject = CanvasObject & {
  backgroundColor?: number;
  borderColor?: number;
  borderWidth?: number;
  elements?: CanvasObject[];
};

export function migrateLegacyNotebookTextStyles(
  objects: CanvasObject[],
): boolean {
  let changed = false;
  const visit = (object: LegacyTextStyleObject): void => {
    if (
      object.type === "text" &&
      object.backgroundColor === 0xffffff &&
      object.borderColor === 0x3b82f6 &&
      object.borderWidth === 2
    ) {
      object.backgroundColor = undefined;
      object.borderColor = undefined;
      object.borderWidth = 0;
      changed = true;
    }
    for (const child of object.elements ?? [])
      visit(child as LegacyTextStyleObject);
  };
  for (const object of objects) visit(object as LegacyTextStyleObject);
  return changed;
}
