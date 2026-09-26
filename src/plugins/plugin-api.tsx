import type { ComponentType, ReactNode } from "react";
import type { ZodType } from "zod";
import {
  PluginCard,
  type CanvasCardObject,
  type CanvasObjectPointerInteractionRegion,
  type CanvasPoint,
  type CanvasPropertiesSlotProps,
} from "@productivity-os/canvas";
import type {
  NotebookSummary,
  PersonRecord,
  SavePersonInput,
} from "@/api/notebook-data";

export type CardPluginManifest = {
  id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  marketplace: boolean;
  defaultInstalled?: boolean;
  card: {
    type: string;
    schemaVersion: number;
    defaultDimensions: { width: number; height: number };
  };
};

export type CardPluginContext = {
  notebookId: string;
  layerId: string;
  point: CanvasPoint;
};

export type CardPluginPropertiesProps = Pick<
  CanvasPropertiesSlotProps,
  "updateObject" | "beginMutation" | "commitMutation" | "cancelMutation"
> & {
  card: PluginCard;
  readOnly: boolean;
};

export type CardPluginToolbarIconProps = {
  className?: string;
  "aria-hidden"?: boolean | "true" | "false";
};

export type CardPluginImageInput = {
  dataUrl: string;
  name: string;
  mimeType: string;
  width: number;
  height: number;
};

export type CardPluginMediaAsset = {
  id: string;
  name: string;
  mimeType: string;
  width: number | null;
  height: number | null;
  url: string;
};

export type CardPluginHostServices = {
  mediaUrl(id: string, variant?: "content" | "thumbnail"): string;
  importImage(input: CardPluginImageInput): Promise<CardPluginMediaAsset>;
  listPersons(query?: string): Promise<PersonRecord[]>;
  savePerson(input: SavePersonInput): Promise<PersonRecord>;
  resolvePersonName(id: string | null | undefined, fallback?: string): string;
  listNotebooks(): Promise<NotebookSummary[]>;
};

export type CardPluginFieldErrors = Record<string, string[]>;

export type CardPluginEditorProps<TDraft> = {
  mode: "create" | "edit";
  draft: TDraft;
  onChange(draft: TDraft): void;
  services: CardPluginHostServices;
  fieldErrors: CardPluginFieldErrors;
};

export type CardPluginEditorAdapter<TData, TDraft> = {
  Component: ComponentType<CardPluginEditorProps<TDraft>>;
  createDraft(data: TData): TDraft;
  schema: ZodType<TDraft>;
  commit(
    draft: TDraft,
    services: CardPluginHostServices,
  ): TData | Promise<TData>;
};

export type CardPluginRenderContext = Pick<
  CardPluginHostServices,
  "mediaUrl" | "resolvePersonName"
> & {
  hovered: boolean;
  hoveredRegionId?: string;
  selected: boolean;
  interactionColor: number;
};

export type CardPluginInlineEditorProps<TData extends Record<string, unknown>> =
  {
    card: PluginCard;
    data: TData;
    regionId: string;
    scale: number;
    onChange(data: TData, height: number): void;
    onRegionChange(regionId: string): void;
    onCancel(): void;
  };

export type CardPluginInlineEditorAdapter<
  TData extends Record<string, unknown>,
> = {
  Component: ComponentType<CardPluginInlineEditorProps<TData>>;
  regions(card: PluginCard): readonly CanvasObjectPointerInteractionRegion[];
  initialRegion(card: PluginCard): string;
  sizePolicy?: "fixed" | "grow-height";
  suppressCardSelection?: boolean;
};

export type CardPluginSlots<TData extends Record<string, unknown>, TDraft> = {
  ToolbarIcon: ComponentType<CardPluginToolbarIconProps>;
  canvasRender(
    card: PluginCard,
    context: CardPluginRenderContext,
  ): CanvasCardObject;
  hoverLabel?(
    card: PluginCard,
    context: CardPluginRenderContext,
  ): string | null;
  Editor?: CardPluginEditorAdapter<TData, TDraft>;
  InlineEditor?: CardPluginInlineEditorAdapter<TData>;
  PropertiesEditor?: ComponentType<CardPluginPropertiesProps>;
  marketplacePreview?: ReactNode;
};

export type CardPluginLifecycleContext = {
  notebookId?: string;
  cardId?: string;
};

export type CardPluginDefinition<
  T extends Record<string, unknown> = Record<string, unknown>,
  TDraft = T,
> = {
  manifest: CardPluginManifest;
  propertiesPanel: "hidden" | "editor";
  create(context: CardPluginContext): PluginCard;
  hydrate(data: unknown): T;
  serialize(data: T): Record<string, unknown>;
  migrate(data: unknown, fromVersion: number): T;
  normalizeCard?(card: PluginCard): boolean;
  slots: CardPluginSlots<T, TDraft>;
  lifecycle: {
    onInstall?(context: CardPluginLifecycleContext): void | Promise<void>;
    onUninstall?(context: CardPluginLifecycleContext): void | Promise<void>;
    onCreate?(context: CardPluginLifecycleContext): void | Promise<void>;
    onActivate?(context: CardPluginLifecycleContext): void | Promise<void>;
    onDelete?(context: CardPluginLifecycleContext): void | Promise<void>;
    dispose?(): void;
  };
};

export function defineCardPlugin<T extends Record<string, unknown>, TDraft = T>(
  definition: CardPluginDefinition<T, TDraft>,
): CardPluginDefinition<T, TDraft> {
  return definition;
}

export function createPluginCard<T extends Record<string, unknown>>(
  manifest: CardPluginManifest,
  context: CardPluginContext,
  data: T,
): PluginCard {
  return new PluginCard({
    id: crypto.randomUUID(),
    layerId: context.layerId,
    type: "card",
    kind: "plugin",
    pluginId: manifest.id,
    pluginVersion: manifest.card.schemaVersion,
    pluginData: data,
    x: context.point.x - manifest.card.defaultDimensions.width / 2,
    y: context.point.y - manifest.card.defaultDimensions.height / 2,
    width: manifest.card.defaultDimensions.width,
    height: manifest.card.defaultDimensions.height,
    elements: [],
    backgroundColor: 0xffffff,
  });
}
