import { useRef, useState } from "react";
import { BookOpen, ImagePlus, X } from "@productivity-os/shared-ui/components/sf-symbols";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import { Progress } from "@productivity-os/shared-ui/components/ui/progress";
import { readNativeClipboardImage } from "@/api/notebook-media";
import type { CardPluginImageInput } from "@/plugins/plugin-api";

type Props = {
  ariaLabel?: string;
  currentUrl?: string | null;
  value: CardPluginImageInput | null;
  removed: boolean;
  onChange(value: CardPluginImageInput | null): void | Promise<void>;
  onRemove(): void;
};

function imageDimensions(
  dataUrl: string,
): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () =>
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    image.onerror = () =>
      reject(new Error("The selected image could not be decoded."));
    image.src = dataUrl;
  });
}

type ProgressReporter = (value: number) => void;

const clipboardImageName = (mimeType: string) => {
  const extension = mimeType.split("/")[1]?.replace("jpeg", "jpg") || "png";
  return `book-cover-${Date.now()}.${extension}`;
};

async function imageInput(
  file: File,
  reportProgress: ProgressReporter,
): Promise<CardPluginImageInput> {
  if (!file.type.startsWith("image/")) {
    throw new Error("Choose or paste an image file.");
  }
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadstart = () => reportProgress(10);
    reader.onprogress = (event) => {
      if (event.lengthComputable) {
        reportProgress(10 + Math.round((event.loaded / event.total) * 65));
      }
    };
    reader.onload = () => {
      reportProgress(78);
      resolve(String(reader.result));
    };
    reader.onerror = () => reject(new Error("The image could not be read."));
    reader.readAsDataURL(file);
  });
  reportProgress(86);
  const dimensions = await imageDimensions(dataUrl);
  reportProgress(96);
  return {
    dataUrl,
    name: file.name.trim() || clipboardImageName(file.type),
    mimeType: file.type,
    ...dimensions,
  };
}

export function BookCoverInput({
  ariaLabel = "Book cover image input",
  currentUrl,
  value,
  removed,
  onChange,
  onRemove,
}: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const importingRef = useRef(false);
  const [message, setMessage] = useState<string | null>(null);
  const [selected, setSelected] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);
  const preview = value?.dataUrl ?? (!removed ? currentUrl : null);

  const reportProgress = (value: number) => {
    setProgress((current) => Math.max(current ?? 0, Math.min(value, 100)));
  };

  const importImage = async (
    load: (report: ProgressReporter) => Promise<CardPluginImageInput>,
  ) => {
    if (importingRef.current) return;
    importingRef.current = true;
    setMessage(null);
    setProgress(4);
    try {
      const next = await load(reportProgress);
      await onChange(next);
      reportProgress(100);
      await new Promise((resolve) => window.setTimeout(resolve, 180));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      importingRef.current = false;
      setProgress(null);
    }
  };

  const acceptFile = async (file: File | null | undefined) => {
    if (!file) return;
    await importImage((report) => imageInput(file, report));
  };

  const paste = async () => {
    await importImage(async (report) => {
      report(12);
      try {
        const nativeImage = await readNativeClipboardImage();
        if (nativeImage) {
          report(92);
          return nativeImage;
        }
      } catch {
        // Fall through to the web Clipboard API when native clipboard reading
        // is unavailable or the clipboard does not currently contain an image.
      }

      report(24);
      if (!navigator.clipboard?.read) {
        throw new Error("Image pasting is not available in this window.");
      }
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const mimeType = item.types.find((type) => type.startsWith("image/"));
        if (!mimeType) continue;
        report(36);
        const blob = await item.getType(mimeType);
        return imageInput(
          new File([blob], clipboardImageName(mimeType), { type: mimeType }),
          (value) => report(36 + Math.round(value * 0.6)),
        );
      }
      throw new Error("The clipboard does not contain an image.");
    });
  };

  return (
    <div className="book-cover-input">
      <div
        className="book-cover-preview"
        data-selected={selected || undefined}
        tabIndex={0}
        aria-label={ariaLabel}
        aria-busy={progress !== null}
        onClick={(event) => {
          event.currentTarget.focus();
        }}
        onFocusCapture={() => setSelected(true)}
        onBlurCapture={(event) => {
          if (
            !event.currentTarget.contains(event.relatedTarget as Node | null)
          ) {
            setSelected(false);
          }
        }}
        onPaste={(event) => {
          if (!selected || importingRef.current) return;
          event.preventDefault();
          const file = Array.from(event.clipboardData.items)
            .find((item) => item.type.startsWith("image/"))
            ?.getAsFile();
          if (file) {
            void acceptFile(file);
          } else {
            void paste();
          }
        }}
      >
        {preview ? (
          <img src={preview} alt="Book cover preview" />
        ) : (
          <span>
            <BookOpen />
            No cover
          </span>
        )}
        <div className="book-cover-overlay">
          <div className="book-cover-overlay-actions">
            <Button
              className="book-cover-upload-action"
              type="button"
              variant="outline"
              disabled={progress !== null}
              onClick={(event) => {
                event.stopPropagation();
                inputRef.current?.click();
              }}
            >
              <ImagePlus />
              Upload
            </Button>
            {preview && (
              <Button
                className="book-cover-clear-action"
                type="button"
                variant="outline"
                disabled={progress !== null}
                onClick={(event) => {
                  event.stopPropagation();
                  setMessage(null);
                  onRemove();
                }}
              >
                <X />
                Clear
              </Button>
            )}
          </div>
        </div>
        {progress !== null && (
          <div className="book-cover-progress" aria-label="Loading book cover">
            <Progress value={progress} />
          </div>
        )}
        <input
          ref={inputRef}
          hidden
          type="file"
          accept="image/*"
          onChange={(event) => {
            const file = event.currentTarget.files?.[0];
            event.currentTarget.value = "";
            void acceptFile(file);
          }}
        />
      </div>
      {message && <small className="book-cover-message">{message}</small>}
    </div>
  );
}
