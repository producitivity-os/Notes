import { Eye, EyeOff, Focus, Layers3, Plus, Trash2 } from "lucide-react";
import type { CanvasLayersSlotProps } from "@productivity-os/canvas";
import type { NotebookDocument } from "@/api/notebook-data";

type Props = CanvasLayersSlotProps & {
  notebook: NotebookDocument;
  open: boolean;
  onMetadata(
    patch: Partial<
      Pick<NotebookDocument, "title" | "project" | "icon" | "coverMediaId">
    >,
  ): void;
};

export function NotebookPanel({
  notebook,
  open,
  onMetadata,
  layers,
  activeLayerId,
  focusedLayerId,
  unfocusedLayerOpacity,
  createLayer,
  updateLayer,
  moveLayer,
  deleteLayer,
  setActiveLayer,
  setFocusedLayer,
  setUnfocusedLayerOpacity,
}: Props) {
  if (!open) return null;
  return (
    <aside
      data-canvas-ui="true"
      className="notebook-panel"
      aria-label="Notebook settings"
      onPointerDown={(event) => event.stopPropagation()}
      onWheel={(event) => event.stopPropagation()}
    >
      <header>
        <span>
          <Layers3 />
          Notebook
        </span>
      </header>
      <div className="metadata-fields">
        <label>
          Title
          <input
            value={notebook.title}
            onChange={(event) =>
              onMetadata({ title: event.currentTarget.value })
            }
          />
        </label>
        <label>
          Folder
          <input
            value={notebook.project}
            onChange={(event) =>
              onMetadata({ project: event.currentTarget.value })
            }
          />
        </label>
        <label>
          Icon
          <input
            value={notebook.icon}
            maxLength={8}
            onChange={(event) =>
              onMetadata({ icon: event.currentTarget.value })
            }
          />
        </label>
        <label>
          Cover
          <input
            value={notebook.coverMediaId ?? ""}
            placeholder="Media ID or URL"
            onChange={(event) =>
              onMetadata({ coverMediaId: event.currentTarget.value || null })
            }
          />
        </label>
      </div>
      <div className="panel-row">
        <strong>Layers</strong>
        <button type="button" title="New layer" onClick={() => createLayer()}>
          <Plus />
        </button>
      </div>
      <div className="layer-list">
        {layers.map((layer, index) => (
          <div
            key={layer.id}
            className="layer-row"
            data-active={layer.id === activeLayerId || undefined}
          >
            <button
              type="button"
              className="layer-name"
              onClick={() => setActiveLayer(layer.id)}
            >
              {layer.name}
            </button>
            <button
              type="button"
              title={layer.visible ? "Hide layer" : "Show layer"}
              onClick={() => updateLayer(layer.id, { visible: !layer.visible })}
            >
              {layer.visible ? <Eye /> : <EyeOff />}
            </button>
            <button
              type="button"
              title="Focus layer"
              aria-pressed={focusedLayerId === layer.id}
              onClick={() =>
                setFocusedLayer(focusedLayerId === layer.id ? null : layer.id)
              }
            >
              <Focus />
            </button>
            <button
              type="button"
              title="Move layer up"
              disabled={index === layers.length - 1}
              onClick={() => moveLayer(layer.id, index + 1)}
            >
              ↑
            </button>
            <button
              type="button"
              title="Move layer down"
              disabled={index === 0}
              onClick={() => moveLayer(layer.id, index - 1)}
            >
              ↓
            </button>
            <button
              type="button"
              title="Delete layer"
              disabled={layers.length === 1}
              onClick={() => deleteLayer(layer.id)}
            >
              <Trash2 />
            </button>
            <label className="layer-control">
              Opacity
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={layer.opacity}
                onChange={(event) =>
                  updateLayer(layer.id, {
                    opacity: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
            <label className="layer-control">
              Color
              <input
                type="color"
                value={`#${(layer.interactionColor ?? 0x3b82f6).toString(16).padStart(6, "0")}`}
                onChange={(event) =>
                  updateLayer(layer.id, {
                    interactionColor: Number.parseInt(
                      event.currentTarget.value.slice(1),
                      16,
                    ),
                  })
                }
              />
            </label>
            <button
              type="button"
              className="rename-layer"
              onClick={() => {
                const name = window.prompt("Layer name", layer.name);
                if (name?.trim()) updateLayer(layer.id, { name: name.trim() });
              }}
            >
              Rename
            </button>
          </div>
        ))}
      </div>
      <label className="focus-opacity">
        Other layers while focused{" "}
        <input
          type="range"
          min="0"
          max="1"
          step="0.05"
          value={unfocusedLayerOpacity}
          onChange={(event) =>
            setUnfocusedLayerOpacity(event.currentTarget.valueAsNumber)
          }
        />
      </label>
    </aside>
  );
}
