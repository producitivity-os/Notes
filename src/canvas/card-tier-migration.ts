import {
  IllustrationCard,
  TextObject,
  type CanvasCardObject,
  type CanvasCardTier,
  type CanvasObject,
  type PluginCard,
  type RevisionCard,
} from "@productivity-os/canvas";

const questionPluginId = "notes.question-card";

function clozeValues(source: string): { prompt: string; answer: string } {
  const pattern = /\{\{c\d+::([\s\S]*?)(?:::([\s\S]*?))?\}\}/g;
  return {
    prompt: source.replace(pattern, (_match, _answer, hint) =>
      hint ? `[${String(hint)}]` : "[…]",
    ),
    answer: source.replace(pattern, (_match, answer) => String(answer)),
  };
}

function textElements(
  card: CanvasCardObject,
  text: string,
  height: number,
): CanvasObject[] {
  const padding = 12;
  return [
    new TextObject({
      id: crypto.randomUUID(),
      layerId: card.layerId,
      type: "text",
      x: padding,
      y: padding,
      width: Math.max(80, card.width - padding * 2),
      height: Math.max(36, height - padding * 2),
      minHeight: Math.max(36, height - padding * 2),
      text,
      format: "markdown",
      sizing: "fixed",
      fontSize: 18,
      lineHeight: 24,
      padding: 0,
    }),
  ];
}

function convertedTiers(card: CanvasCardObject): CanvasCardTier[] | null {
  const legacy = card as CanvasCardObject &
    Partial<Pick<RevisionCard, "revisionKind" | "front" | "back" | "cloze">> &
    Partial<Pick<PluginCard, "pluginId" | "pluginData">>;
  const values: Record<string, unknown> | null =
    card.kind === "plugin" && legacy.pluginId === questionPluginId
      ? legacy.pluginData ?? {}
      : card.kind === "revision"
        ? {
            revisionKind: legacy.revisionKind,
            front: legacy.front,
            back: legacy.back,
            cloze: legacy.cloze,
          }
        : null;
  if (!values) return null;

  const revisionKind = String(values.revisionKind ?? "basic");
  const source = String(values.cloze ?? "");
  const cloze = clozeValues(source);
  const front = revisionKind === "cloze" ? cloze.prompt : String(values.front ?? "");
  const back = revisionKind === "cloze" ? cloze.answer : String(values.back ?? "");
  const frontHeight = Math.max(60, Number(values.frontHeight) || card.height);
  const backHeight = Math.max(60, Number(values.backHeight) || card.height);
  return [
    {
      id: "front",
      name: "Front",
      kind: "canvas",
      width: card.width,
      height: frontHeight,
      revision: 1,
      elements: textElements(card, front, frontHeight),
    },
    {
      id: "back",
      name: "Back",
      kind: "canvas",
      width: card.width,
      height: backHeight,
      revision: 1,
      elements: textElements(card, back, backHeight),
    },
  ];
}

export function migrateLegacyQuestionCards(objects: CanvasObject[]): boolean {
  let changed = false;
  for (let index = 0; index < objects.length; index += 1) {
    const object = objects[index];
    if (object?.type !== "card") continue;
    const card = object as CanvasCardObject;
    const tiers = convertedTiers(card);
    if (tiers) {
      const centerY = card.y + card.height / 2;
      const converted = new IllustrationCard({
        ...structuredClone(card),
        kind: "canvas",
        height: tiers[0].height,
        y: centerY - tiers[0].height / 2,
        tiers,
        backgroundColor: card.backgroundColor ?? 0xffffff,
      });
      objects[index] = converted;
      changed = true;
      continue;
    }
    for (const tier of card.tiers)
      changed = migrateLegacyQuestionCards(tier.elements) || changed;
  }
  return changed;
}
