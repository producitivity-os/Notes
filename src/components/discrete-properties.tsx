import {
  AlignCenter,
  AlignLeft,
  AlignRight,
  Bold,
  CaseSensitive,
  Check,
  CircleOff,
  Italic,
  Underline,
} from "@productivity-os/shared-ui/components/sf-symbols";
import {
  CANVAS_MIXED_VALUE,
  type CanvasPropertiesSlotProps,
  type CanvasPropertyField,
  type CanvasPropertyPatch,
  type CanvasCardObject,
  type PluginCard,
} from "@productivity-os/canvas";
import type { CardPluginDefinition } from "@/plugins/plugin-api";
import type { NotebookSummary } from "@/api/notebook-data";
import { Button } from "@productivity-os/shared-ui/components/ui/button";

type Props = CanvasPropertiesSlotProps & {
  plugin: CardPluginDefinition | null;
  pluginInstalled: boolean;
  notebooks: readonly NotebookSummary[];
  onEditTiers(card: CanvasCardObject): void;
};

const COLORS = [0x1f2530, 0xffffff, 0x94a3b8, 0x3b82f6, 0xef4444];
const equals = (value: unknown, option: unknown) =>
  value !== CANVAS_MIXED_VALUE && value === option;

export function DiscreteProperties({
  context,
  selection,
  onPatch,
  updateObject,
  beginMutation,
  commitMutation,
  cancelMutation,
  plugin,
  pluginInstalled,
  notebooks,
  onEditTiers,
}: Props) {
  const selectedCard =
    selection.selectedObjects.length === 1 &&
    selection.selectedObjects[0]?.type === "card"
      ? (selection.selectedObjects[0] as CanvasCardObject)
      : null;
  const selected =
    selectedCard?.kind === "plugin"
      ? (selectedCard as PluginCard)
      : null;
  if (selected && !plugin)
    return (
      <Panel title="Plugin unavailable">
        <p>This card is preserved. Reinstall its plugin to edit it.</p>
        <TierButton card={selected} onEdit={onEditTiers} />
      </Panel>
    );
  if (selected && plugin && !pluginInstalled)
    return (
      <Panel title={`${plugin.manifest.name} · read only`}>
        <p>Reinstall this plugin to edit the card.</p>
        <TierButton card={selected} onEdit={onEditTiers} />
      </Panel>
    );
  if (selected && plugin?.propertiesPanel === "hidden")
    return (
      <Panel title={plugin.manifest.name}>
        <TierButton card={selected} onEdit={onEditTiers} />
      </Panel>
    );
  if (selected && selected.pluginId === "notes.notebook-card") {
    const data = selected.pluginData;
    return (
      <Panel title="Notebook card">
        <TierButton card={selected} onEdit={onEditTiers} />
        <label>
          Target
          <select
            value={String(data.targetNotebookId ?? "")}
            onChange={(event) => {
              const notebook = notebooks.find(
                (item) => item.id === event.currentTarget.value,
              );
              updateObject(selected.id, {
                pluginData: {
                  ...data,
                  targetNotebookId: notebook?.id ?? "",
                  targetNotebookTitle: notebook?.title ?? "Missing notebook",
                },
              } as Partial<PluginCard>);
            }}
          >
            <option value="">Choose a notebook</option>
            {notebooks.map((notebook) => (
              <option key={notebook.id} value={notebook.id}>
                {notebook.title}
              </option>
            ))}
          </select>
        </label>
      </Panel>
    );
  }
  if (selected && plugin) {
    const Editor = plugin.slots.PropertiesEditor;
    return (
      <Panel
        title={
          pluginInstalled
            ? plugin.manifest.name
            : `${plugin.manifest.name} · read only`
        }
      >
        <TierButton card={selected} onEdit={onEditTiers} />
        {Editor ? (
          <Editor
            card={selected}
            readOnly={!pluginInstalled}
            updateObject={updateObject}
            beginMutation={beginMutation}
            commitMutation={commitMutation}
            cancelMutation={cancelMutation}
          />
        ) : (
          <p>No editable properties.</p>
        )}
      </Panel>
    );
  }
  if (context.fields.length === 0)
    return selectedCard ? (
      <Panel title="Card">
        <TierButton card={selectedCard} onEdit={onEditTiers} />
      </Panel>
    ) : null;
  return (
    <Panel
      title={
        context.mode === "selection"
          ? context.selectionCount === 1
            ? "Properties"
            : `${context.selectionCount} selected`
          : "Defaults"
      }
    >
      {selectedCard && (
        <TierButton card={selectedCard} onEdit={onEditTiers} />
      )}
      {context.fields.map((field) => (
        <PresetField key={field.name} field={field} onPatch={onPatch} />
      ))}
    </Panel>
  );
}

function TierButton({
  card,
  onEdit,
}: {
  card: CanvasCardObject;
  onEdit(card: CanvasCardObject): void;
}) {
  return (
    <Button type="button" variant="outline" onClick={() => onEdit(card)}>
      Edit tiers · {card.tiers.length}
    </Button>
  );
}

function Panel({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <aside
      data-canvas-ui="true"
      className="properties-panel"
      aria-label={title}
      onPointerDown={(event) => event.stopPropagation()}
      onWheel={(event) => event.stopPropagation()}
    >
      <h2>{title}</h2>
      {children}
    </aside>
  );
}

function PresetField({
  field,
  onPatch,
}: {
  field: CanvasPropertyField;
  onPatch(patch: CanvasPropertyPatch): void;
}) {
  const patch = (value: unknown) =>
    onPatch({ [field.name]: value } as CanvasPropertyPatch);
  let options: Array<{
    value: unknown;
    label: string;
    icon?: React.ReactNode;
  }> = [];
  if (field.name === "fontSize")
    options = [
      { value: 14, label: "S" },
      { value: 18, label: "M" },
      { value: 24, label: "L" },
      { value: 32, label: "XL" },
    ];
  else if (field.name === "lineHeight")
    options = [
      { value: 20, label: "S" },
      { value: 24, label: "M" },
      { value: 32, label: "L" },
      { value: 40, label: "XL" },
    ];
  else if (field.name === "fontFamily")
    options = [
      { value: "inter", label: "Sans" },
      { value: "serif", label: "Serif" },
      { value: "mono", label: "Mono" },
      { value: "rounded", label: "Rounded" },
    ];
  else if (field.name === "weight")
    options = [
      { value: "regular", label: "Regular", icon: <CaseSensitive /> },
      { value: "bold", label: "Bold", icon: <Bold /> },
      { value: "extrabold", label: "Extra Bold", icon: <Bold /> },
    ];
  else if (field.name === "opacity")
    options = [0.25, 0.5, 0.75, 1].map((value) => ({
      value,
      label: `${value * 100}%`,
    }));
  else if (field.name === "strokeWidth")
    options = [1, 2, 4, 8].map((value) => ({ value, label: String(value) }));
  else if (field.name === "cornerRadius")
    options = [0, 8, 24].map((value) => ({ value, label: String(value) }));
  else if (field.control === "color")
    options = COLORS.map((value) => ({
      value,
      label: `#${value.toString(16).padStart(6, "0")}`,
    }));
  else if (field.control === "select")
    options = (field.options ?? []).map((option) => ({
      value: option.value,
      label: option.label,
    }));
  else if (field.control === "boolean")
    options = [
      { value: true, label: "On", icon: <Check /> },
      { value: false, label: "Off", icon: <CircleOff /> },
    ];
  else if (field.name === "italic")
    options = [
      { value: true, label: "Italic", icon: <Italic /> },
      { value: false, label: "Plain" },
    ];
  else if (field.name === "underline")
    options = [
      { value: true, label: "Underline", icon: <Underline /> },
      { value: false, label: "None" },
    ];
  else if (
    field.control === "number" &&
    field.min !== undefined &&
    field.max !== undefined
  )
    options = [field.min, (field.min + field.max) / 2, field.max].map(
      (value) => ({ value, label: Number(value.toFixed(2)).toString() }),
    );
  if (field.name === "textAlign")
    options = [
      { value: "left", label: "Left", icon: <AlignLeft /> },
      { value: "center", label: "Center", icon: <AlignCenter /> },
      { value: "right", label: "Right", icon: <AlignRight /> },
    ];
  if (options.length === 0) return null;
  return (
    <section className="property-group">
      <span>{field.label}</span>
      <div className="preset-grid">
        {options.map((option) => (
          <Button
            key={String(option.value)}
            type="button"
            variant="outline"
            size="icon"
            className="property-preset-button"
            title={`${field.label}: ${option.label}`}
            aria-label={`${field.label}: ${option.label}`}
            aria-pressed={equals(field.value, option.value)}
            onClick={() => {
              if (field.name === "fontSize") {
                const lineHeight = (
                  { 14: 20, 18: 24, 24: 32, 32: 40 } as Record<number, number>
                )[option.value as number];
                onPatch({ fontSize: option.value as number, lineHeight });
              } else patch(option.value);
            }}
          >
            {field.control === "color" ? (
              <i style={{ background: option.label }} />
            ) : (
              (option.icon ?? option.label)
            )}
          </Button>
        ))}
      </div>
    </section>
  );
}
