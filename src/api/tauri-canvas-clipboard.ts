import { Image as TauriImage } from "@tauri-apps/api/image";
import {
  readImage,
  readText,
  writeImage,
  writeText,
} from "@tauri-apps/plugin-clipboard-manager";
import {
  canvasClipboardText,
  ClipboardImageCodec,
  systemClipboardPayloadFromText,
  type CanvasObject,
  type CanvasSystemClipboard,
  type SystemClipboardPayload,
} from "@productivity-os/canvas";
import { isTauri } from "./notebook-data";

export class TauriCanvasClipboard implements CanvasSystemClipboard {
  private readonly images = new ClipboardImageCodec();

  async write(
    elements: readonly CanvasObject[],
    token: string,
  ): Promise<string> {
    const plainText = canvasClipboardText(elements, token);
    const image =
      elements.length === 1 && elements[0].type === "image"
        ? (elements[0] as unknown as { src: string })
        : null;

    if (image) {
      try {
        const pixels = await this.images.decodeSource(image.src);
        const nativeImage = await TauriImage.new(
          pixels.rgba,
          pixels.width,
          pixels.height,
        );
        try {
          await writeImage(nativeImage);
        } finally {
          await nativeImage.close();
        }
        return await this.images.fingerprint(pixels);
      } catch {
        // Keep editable canvas objects available through the text fallback.
      }
    }

    await writeText(plainText);
    return plainText;
  }

  async read(): Promise<SystemClipboardPayload> {
    try {
      const nativeImage = await readImage();
      try {
        const [rgba, size] = await Promise.all([
          nativeImage.rgba(),
          nativeImage.size(),
        ]);
        const image = { rgba, width: size.width, height: size.height };
        return {
          kind: "image",
          dataUrl: this.images.encodePngDataUrl(image),
          mimeType: "image/png",
          fingerprint: await this.images.fingerprint(image),
        };
      } finally {
        await nativeImage.close();
      }
    } catch {
      // A text-only clipboard is expected to reject image reads.
    }

    try {
      return systemClipboardPayloadFromText(await readText());
    } catch {
      return { kind: "empty" };
    }
  }
}

export const createTauriCanvasClipboard = ():
  CanvasSystemClipboard | undefined =>
  isTauri ? new TauriCanvasClipboard() : undefined;
