import { useEffect, useMemo, useRef, useState } from "react";
import {
  EndlessCanvas,
  canvasObjectFactory,
  type CanvasCardObject,
  type CanvasObject,
  type EndlessCanvasHandle,
  type EndlessCanvasOptions,
  type EndlessCanvasState,
} from "@productivity-os/canvas";
import { notebookData } from "@/api/notebook-data";

type Props = {
  notebookId: string;
  card: CanvasCardObject;
  options: EndlessCanvasOptions;
  onComplete(): void;
};

const previewLayer = (tierId: string) => `tier-preview-${tierId}`;
const previewScale = (width: number, height: number) =>
  Math.min(1, 900 / Math.max(1, width), 640 / Math.max(1, height));

function previewObjects(
  card: CanvasCardObject,
  tierIndex: number,
): CanvasObject[] {
  const tier = card.tiers[tierIndex];
  if (!tier) return [];
  const layerId = previewLayer(tier.id);
  if (tierIndex === 0 && tier.kind !== "canvas") {
    return [
      canvasObjectFactory.hydrate({
        ...structuredClone(card),
        x: 0,
        y: 0,
        width: tier.width,
        height: tier.height,
        layerId,
      } as unknown as CanvasObject),
    ];
  }
  return structuredClone(tier.elements).map((element) =>
    canvasObjectFactory.hydrate({ ...element, layerId } as CanvasObject),
  );
}

function previewState(card: CanvasCardObject, tierIndex: number): EndlessCanvasState {
  const tier = card.tiers[tierIndex];
  const layerId = previewLayer(tier.id);
  const scale = previewScale(tier.width, tier.height);
  return {
    activeLayerId: layerId,
    focusedLayerId: null,
    unfocusedLayerOpacity: 1,
    viewport: { x: 0, y: 0, scale },
    layers: [
      {
        id: layerId,
        name: tier.name,
        zIndex: 0,
        visible: true,
        opacity: 1,
        interactionColor: 0x3b82f6,
      },
    ],
    objects: previewObjects(card, tierIndex),
  };
}

export function CardTierPreviewRegenerator({
  notebookId,
  card,
  options,
  onComplete,
}: Props) {
  const canvasRef = useRef<EndlessCanvasHandle>(null);
  const onCompleteRef = useRef(onComplete);
  onCompleteRef.current = onComplete;
  const [tierIndex, setTierIndex] = useState(0);
  const [ready, setReady] = useState(false);
  const tier = card.tiers[tierIndex];
  const state = useMemo(
    () => (tier ? previewState(card, tierIndex) : null),
    [card, tier, tierIndex],
  );
  const previewOptions = useMemo<EndlessCanvasOptions>(
    () => ({ ...options, maxPaneDepth: 0, canInsertObject: () => false }),
    [options],
  );

  useEffect(() => {
    if (!tier) onCompleteRef.current();
  }, [tier]);

  useEffect(() => {
    if (!ready || !tier) return;
    let cancelled = false;
    const timer = window.setTimeout(() => {
      const capture = async () => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const dataUrl = await canvas.captureSnapshot({
          format: "jpeg",
          quality: 0.8,
          resolution: 0.5,
        });
        if (!dataUrl) return;
        await notebookData.saveCardTierPreviews([
          {
            documentId: notebookId,
            cardId: card.id,
            tierId: tier.id,
            tierRevision: tier.revision,
            dataUrl,
          },
        ]);
      };
      void capture()
        .catch(console.error)
        .finally(() => {
          if (cancelled) return;
          if (tierIndex + 1 < card.tiers.length) {
            setReady(false);
            setTierIndex((index) => index + 1);
          } else {
            onCompleteRef.current();
          }
        });
    }, 350);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [card.id, card.tiers.length, notebookId, ready, tier, tierIndex]);

  if (!tier || !state) return null;

  const scale = previewScale(tier.width, tier.height);

  return (
    <div className="card-tier-preview-regenerator" aria-hidden="true">
      <div
        style={{
          width: Math.max(1, tier.width * scale),
          height: Math.max(1, tier.height * scale),
        }}
      >
        <EndlessCanvas
          key={tier.id}
          ref={canvasRef}
          tool="select"
          initialState={state}
          options={previewOptions}
          onReady={() => setReady(true)}
          style={{ width: "100%", height: "100%" }}
        />
      </div>
    </div>
  );
}
