import type {
  CanvasObject,
  CanvasPluginCardDefinition,
  CanvasPluginCardProvider,
  PluginCard,
} from "@productivity-os/canvas";
import { permanentCards } from "./builtin-cards";
import { importNotebookImage, notebookMediaUrl } from "@/api/notebook-media";
import {
  notebookData,
  personData,
  type PersonRecord,
} from "@/api/notebook-data";
import type {
  CardPluginDefinition,
  CardPluginHostServices,
} from "./plugin-api";

type PluginDefinition = CardPluginDefinition<any, any>;
type PluginModule = { default: PluginDefinition };
const modules = import.meta.glob<PluginModule>(
  "../../../../plugins/*/index.tsx",
  { eager: true },
);

export class NotesPluginRegistry implements CanvasPluginCardProvider {
  private readonly definitions = new Map<string, PluginDefinition>();
  private readonly listeners = new Set<() => void>();
  private installed = new Set<string>();
  private readonly persons = new Map<string, PersonRecord>();

  constructor() {
    for (const definition of permanentCards)
      this.definitions.set(definition.manifest.id, definition);
    for (const module of Object.values(modules)) {
      const definition = module.default;
      if (definition?.manifest?.id)
        this.definitions.set(definition.manifest.id, definition);
    }
  }

  get(pluginId: string): CanvasPluginCardDefinition | null {
    const plugin = this.definitions.get(pluginId);
    if (!plugin) return null;
    return {
      id: plugin.manifest.id,
      width: plugin.manifest.card.defaultDimensions.width,
      height: plugin.manifest.card.defaultDimensions.height,
      sizePolicy: plugin.slots.InlineEditor?.sizePolicy,
      materialize: (card: PluginCard, renderContext) =>
        plugin.slots.canvasRender(card, {
          mediaUrl: notebookMediaUrl,
          resolvePersonName: (id, fallback = "") =>
            (id && this.persons.get(id)?.name) || fallback,
          ...renderContext,
        }),
      hoverLabel: (card: PluginCard) =>
        plugin.slots.hoverLabel?.(card, {
          mediaUrl: notebookMediaUrl,
          resolvePersonName: (id, fallback = "") =>
            (id && this.persons.get(id)?.name) || fallback,
          hovered: false,
          selected: false,
          interactionColor: 0x3b82f6,
        }) ?? null,
    };
  }

  definition(pluginId: string): PluginDefinition | null {
    return this.definitions.get(pluginId) ?? null;
  }

  marketplace(): PluginDefinition[] {
    return [...this.definitions.values()].filter(
      (plugin) => plugin.manifest.marketplace,
    );
  }

  availableCards(): PluginDefinition[] {
    return [
      ...permanentCards,
      ...this.marketplace().filter((plugin) =>
        this.installed.has(plugin.manifest.id),
      ),
    ];
  }

  isInstalled(pluginId: string): boolean {
    return (
      permanentCards.some((plugin) => plugin.manifest.id === pluginId) ||
      this.installed.has(pluginId)
    );
  }

  hostServices(notebookId: string): CardPluginHostServices {
    return {
      mediaUrl: notebookMediaUrl,
      importImage: (input) => importNotebookImage(notebookId, input),
      listPersons: (query) => personData.list(query),
      savePerson: async (input) => {
        const person = await personData.save(input);
        this.setPersons([person], false);
        return person;
      },
      resolvePersonName: (id, fallback = "") =>
        (id && this.persons.get(id)?.name) || fallback,
      listNotebooks: () => notebookData.list(),
    };
  }

  setPersons(persons: Iterable<PersonRecord>, replace = true): void {
    if (replace) this.persons.clear();
    for (const person of persons) this.persons.set(person.id, person);
    this.notify();
  }

  migrateCards(objects: readonly CanvasObject[]): boolean {
    let changed = false;
    for (const object of objects) {
      if (object.type !== "card") continue;
      const card = object as PluginCard;
      if (card.kind === "plugin") {
        const plugin = this.definitions.get(card.pluginId);
        const targetVersion = plugin?.manifest.card.schemaVersion;
        if (plugin && targetVersion && card.pluginVersion < targetVersion) {
          card.pluginData = plugin.serialize(
            plugin.migrate(card.pluginData, card.pluginVersion),
          );
          card.pluginVersion = targetVersion;
          changed = true;
        }
        if (plugin?.normalizeCard?.(card)) changed = true;
        const nameField =
          card.pluginId === "notes.book-card"
            ? "authorName"
            : card.pluginId === "notes.person-card"
              ? "name"
              : null;
        const idField =
          card.pluginId === "notes.book-card"
            ? "authorPersonId"
            : card.pluginId === "notes.person-card"
              ? "personId"
              : null;
        if (nameField && idField && !card.pluginData[idField]) {
          const name = String(card.pluginData[nameField] ?? "").trim();
          const match = [...this.persons.values()].find(
            (person) =>
              person.name.trim().toLocaleLowerCase() ===
              name.toLocaleLowerCase(),
          );
          if (match) {
            card.pluginData = { ...card.pluginData, [idField]: match.id };
            changed = true;
          }
        }
      }
      for (const tier of card.tiers)
        changed = this.migrateCards(tier.elements) || changed;
    }
    return changed;
  }

  setInstallations(pluginIds: Iterable<string>): void {
    this.installed = new Set(pluginIds);
    this.notify();
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  dispose(): void {
    for (const plugin of this.definitions.values())
      plugin.lifecycle.dispose?.();
    this.listeners.clear();
  }

  private notify(): void {
    for (const listener of this.listeners) listener();
  }
}

export const notesPlugins = new NotesPluginRegistry();
