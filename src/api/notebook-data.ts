import { invoke } from "@tauri-apps/api/core";
import {
  canvasObjectFactory,
  type CanvasLayer,
  type CanvasObject,
  type EndlessCanvasState,
} from "@productivity-os/canvas";

export type NotebookSummary = {
  id: string;
  title: string;
  project: string;
  canvasType: "notebook";
  icon: string;
  starred: boolean;
  createdAt: number;
  updatedAt: number;
  revision: number;
  previewDataUrl: string | null;
  coverMediaId: string | null;
};

export type CanvasSnapshot = {
  schemaVersion: number;
  activeLayerId: string;
  focusedLayerId: string | null;
  unfocusedLayerOpacity: number;
  viewport: { x: number; y: number; scale: number };
  layers: Array<{
    id: string;
    name: string;
    zIndex: number;
    visible: boolean;
    opacity: number;
    interactionColor: number;
  }>;
  objects: Array<{
    id: string;
    layerId: string;
    objectType: string;
    sortIndex: number;
    payload: Record<string, unknown>;
  }>;
};

export type NotebookDocument = NotebookSummary & { canvas: CanvasSnapshot };
export type SaveNotebookInput = Omit<
  NotebookSummary,
  "createdAt" | "updatedAt" | "revision" | "previewDataUrl"
> & {
  expectedRevision: number | null;
  canvas: CanvasSnapshot;
};
export type PluginInstallation = {
  pluginId: string;
  installed: boolean;
  installedAt: number | null;
};
export type InitialNavigation = { notebookId: string; objectId: string | null };
export type CardTierPreviewInput = {
  documentId: string;
  cardId: string;
  tierId: string;
  tierRevision: number;
  dataUrl: string;
};
export type PersonRecord = {
  id: string;
  name: string;
  role: string;
  organization: string;
  notes: string;
  createdAt: number;
  updatedAt: number;
};
export type SavePersonInput = Pick<
  PersonRecord,
  "id" | "name" | "role" | "organization" | "notes"
>;

export const isTauri =
  typeof window !== "undefined" &&
  ("__TAURI_INTERNALS__" in window || "__TAURI__" in window);
const memory = new Map<string, NotebookDocument>();
const memoryPlugins = new Map<string, PluginInstallation>();
const memoryPersons = new Map<string, PersonRecord>();
const clone = <T>(value: T): T => structuredClone(value);

export function createEmptyNotebookState(): EndlessCanvasState {
  return {
    layers: [
      {
        id: "main",
        name: "Main",
        zIndex: 0,
        visible: true,
        opacity: 1,
        interactionColor: 0x3b82f6,
      },
    ],
    activeLayerId: "main",
    focusedLayerId: null,
    unfocusedLayerOpacity: 0.25,
    viewport: { x: 0, y: 0, scale: 1 },
    objects: [],
  };
}

export function canvasToSnapshot(state: EndlessCanvasState): CanvasSnapshot {
  const layers = state.layers ?? [];
  return {
    schemaVersion: 6,
    activeLayerId: state.activeLayerId ?? layers[0]?.id ?? "main",
    focusedLayerId: state.focusedLayerId ?? null,
    unfocusedLayerOpacity: state.unfocusedLayerOpacity ?? 0.25,
    viewport: {
      x: state.viewport?.x ?? 0,
      y: state.viewport?.y ?? 0,
      scale: state.viewport?.scale ?? 1,
    },
    layers: layers.map((layer) => ({
      ...layer,
      interactionColor: layer.interactionColor ?? 0x3b82f6,
    })),
    objects: state.objects.map((object, sortIndex) => ({
      id: object.id,
      layerId: object.layerId,
      objectType: object.type,
      sortIndex,
      payload: JSON.parse(JSON.stringify(object)) as Record<string, unknown>,
    })),
  };
}

export function snapshotToCanvas(snapshot: CanvasSnapshot): EndlessCanvasState {
  return {
    activeLayerId: snapshot.activeLayerId,
    focusedLayerId: snapshot.focusedLayerId,
    unfocusedLayerOpacity: snapshot.unfocusedLayerOpacity,
    viewport: clone(snapshot.viewport),
    layers: clone(snapshot.layers) as CanvasLayer[],
    objects: snapshot.objects
      .slice()
      .sort((a, b) => a.sortIndex - b.sortIndex)
      .map((object) =>
        canvasObjectFactory.hydrate(
          clone(object.payload) as unknown as CanvasObject,
        ),
      ),
  };
}

function saveMemory(input: SaveNotebookInput): NotebookSummary {
  const previous = memory.get(input.id);
  const summary: NotebookSummary = {
    id: input.id,
    title: input.title,
    project: input.project,
    canvasType: "notebook",
    icon: input.icon,
    starred: input.starred,
    coverMediaId: input.coverMediaId,
    createdAt: previous?.createdAt ?? Date.now(),
    updatedAt: Date.now(),
    revision: (previous?.revision ?? 0) + 1,
    previewDataUrl: previous?.previewDataUrl ?? null,
  };
  memory.set(input.id, { ...summary, canvas: clone(input.canvas) });
  return clone(summary);
}

export const notebookData = {
  async list(): Promise<NotebookSummary[]> {
    if (isTauri) return invoke("list_notebooks");
    return [...memory.values()]
      .map(({ canvas: _canvas, ...summary }) => clone(summary))
      .sort((a, b) => b.updatedAt - a.updatedAt);
  },
  async get(id: string): Promise<NotebookDocument | null> {
    if (isTauri) return invoke("get_notebook", { id });
    return clone(memory.get(id) ?? null);
  },
  async save(input: SaveNotebookInput): Promise<NotebookSummary> {
    if (isTauri) return invoke("save_notebook", { input });
    return saveMemory(input);
  },
  async update(
    id: string,
    patch: Partial<
      Pick<
        NotebookSummary,
        "title" | "project" | "icon" | "starred" | "coverMediaId"
      >
    >,
  ): Promise<NotebookSummary | null> {
    if (isTauri) return invoke("update_notebook", { id, patch });
    const current = memory.get(id);
    return current
      ? saveMemory({ ...current, ...patch, expectedRevision: current.revision })
      : null;
  },
  async delete(id: string): Promise<boolean> {
    if (isTauri) return invoke("delete_notebook", { id });
    return memory.delete(id);
  },
  async savePreview(id: string, dataUrl: string): Promise<boolean> {
    if (isTauri) return invoke("save_notebook_preview", { id, dataUrl });
    const current = memory.get(id);
    if (!current) return false;
    current.previewDataUrl = dataUrl;
    return true;
  },
  async saveCardTierPreviews(
    previews: CardTierPreviewInput[],
  ): Promise<boolean> {
    if (isTauri) return invoke("save_card_tier_previews", { previews });
    return true;
  },
  async open(
    id: string,
    title: string,
    focusObjectId?: string | null,
  ): Promise<void> {
    if (isTauri)
      await invoke("open_notebook_window", {
        id,
        title,
        focusObjectId: focusObjectId ?? null,
      });
    else window.location.assign(`/notebook/${encodeURIComponent(id)}`);
  },
  async initialNavigation(): Promise<InitialNavigation | null> {
    if (!isTauri) return null;
    return invoke("initial_navigation");
  },
  async focusHome(): Promise<void> {
    if (isTauri) await invoke("focus_notes_home");
    else window.location.assign("/");
  },
  async revise(id: string): Promise<void> {
    if (isTauri) await invoke("open_revise_for_notebook", { id });
  },
};

export const pluginData = {
  async list(): Promise<PluginInstallation[]> {
    if (isTauri) return invoke("list_plugin_installations");
    return [...memoryPlugins.values()].map(clone);
  },
  async setInstalled(
    pluginId: string,
    installed: boolean,
  ): Promise<PluginInstallation> {
    if (isTauri) return invoke("set_plugin_installed", { pluginId, installed });
    const value = {
      pluginId,
      installed,
      installedAt: installed ? Date.now() : null,
    };
    memoryPlugins.set(pluginId, value);
    window.dispatchEvent(new CustomEvent("notes:plugins-changed"));
    return value;
  },
};

const normalizedPersonName = (name: string) => name.trim().toLocaleLowerCase();

export const personData = {
  async list(query?: string): Promise<PersonRecord[]> {
    if (isTauri)
      return invoke("list_notes_persons", { query: query?.trim() || null });
    const normalizedQuery = normalizedPersonName(query ?? "");
    return [...memoryPersons.values()]
      .filter(
        (person) =>
          !normalizedQuery ||
          normalizedPersonName(person.name).includes(normalizedQuery),
      )
      .sort((a, b) => a.name.localeCompare(b.name))
      .map(clone);
  },
  async save(input: SavePersonInput): Promise<PersonRecord> {
    if (isTauri) return invoke("save_notes_person", { input });
    const normalizedName = normalizedPersonName(input.name);
    const exact = [...memoryPersons.values()].find(
      (person) => normalizedPersonName(person.name) === normalizedName,
    );
    if (exact && exact.id !== input.id) return clone(exact);
    const now = Date.now();
    const value: PersonRecord = {
      ...input,
      name: input.name.trim(),
      role: input.role.trim(),
      organization: input.organization.trim(),
      notes: input.notes.trim(),
      createdAt: exact?.createdAt ?? now,
      updatedAt: now,
    };
    memoryPersons.set(value.id, value);
    window.dispatchEvent(
      new CustomEvent("notes:persons-changed", { detail: clone(value) }),
    );
    return clone(value);
  },
};
