import type {
  CanvasPluginCardDefinition,
  CanvasPluginCardProvider,
  PluginCard,
} from "@productivity-os/canvas"
import { permanentCards } from "@/plugins/builtin-cards"
import type { CardPluginDefinition } from "@/plugins/plugin-api"

const definitions = new Map<string, CardPluginDefinition<any, any>>(
  permanentCards.map((definition) => [definition.manifest.id, definition]),
)

export function nativeMediaURL(identifier: string) {
  return identifier.startsWith("notebook-asset://") || identifier.startsWith("notes-canvas://")
    ? identifier
    : ""
}

export function nativePluginDefinition(pluginID: string) {
  return definitions.get(pluginID) ?? null
}

export const nativePluginCards: CanvasPluginCardProvider = {
  get(pluginID: string): CanvasPluginCardDefinition | null {
    const plugin = definitions.get(pluginID)
    if (!plugin) return null
    return {
      id: plugin.manifest.id,
      width: plugin.manifest.card.defaultDimensions.width,
      height: plugin.manifest.card.defaultDimensions.height,
      sizePolicy: plugin.slots.InlineEditor?.sizePolicy,
      materialize: (card: PluginCard, renderContext) =>
        plugin.slots.canvasRender(card, {
          mediaUrl: nativeMediaURL,
          resolvePersonName: (_id, fallback = "") => fallback,
          ...renderContext,
        }),
      hoverLabel: (card: PluginCard) =>
        plugin.slots.hoverLabel?.(card, {
          mediaUrl: nativeMediaURL,
          resolvePersonName: (_id, fallback = "") => fallback,
          hovered: false,
          selected: false,
          interactionColor: 0x3b82f6,
        }) ?? null,
    }
  },
}
