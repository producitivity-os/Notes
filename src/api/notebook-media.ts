import { invoke } from "@tauri-apps/api/core";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { ClipboardImageCodec } from "@productivity-os/canvas";
import type {
  CardPluginImageInput,
  CardPluginMediaAsset,
} from "@/plugins/plugin-api";
import { isTauri } from "./notebook-data";

export type NotebookMediaKind =
  "image" | "video" | "audio" | "pdf" | "document" | "file";
export type NotebookMediaEntry = {
  id: string;
  canvasId: string;
  canvasTitle: string;
  originalName: string;
  mimeType: string;
  kind: NotebookMediaKind;
  sizeBytes: number;
  width: number | null;
  height: number | null;
  hasThumbnail: boolean;
  hasProxy: boolean;
  createdAt: number;
};
export type NotebookMediaCursor = { createdAt: number; id: string };
export type NotebookMediaQuery = {
  canvasId?: string | null;
  query?: string | null;
  kind?: NotebookMediaKind | null;
  cursor?: NotebookMediaCursor | null;
  limit?: number;
};
export type NotebookMediaPage = {
  items: NotebookMediaEntry[];
  nextCursor: NotebookMediaCursor | null;
};
export type NotebookMediaImportResult = {
  imported: NotebookMediaEntry[];
  duplicates: NotebookMediaEntry[];
  failures: Array<{ name: string; message: string }>;
};

type BrowserMedia = { entry: NotebookMediaEntry; url: string };
const browserMedia = new Map<string, BrowserMedia>();

function mediaKind(file: Pick<File, "name" | "type">): NotebookMediaKind {
  const mime = file.type.toLocaleLowerCase();
  const extension = file.name.split(".").pop()?.toLocaleLowerCase();
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  if (mime === "application/pdf" || extension === "pdf") return "pdf";
  if (
    mime.startsWith("text/") ||
    ["doc", "docx", "md", "txt", "rtf", "xls", "xlsx", "ppt", "pptx"].includes(
      extension ?? "",
    )
  )
    return "document";
  return "file";
}

function chooseBrowserFiles(): Promise<File[]> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.multiple = true;
    input.onchange = () => resolve(Array.from(input.files ?? []));
    input.oncancel = () => resolve([]);
    input.click();
  });
}

async function browserImport(
  canvasId: string,
  files: File[],
): Promise<NotebookMediaImportResult> {
  const result: NotebookMediaImportResult = {
    imported: [],
    duplicates: [],
    failures: [],
  };
  for (const file of files) {
    const duplicate = [...browserMedia.values()].find(
      ({ entry }) =>
        entry.canvasId === canvasId &&
        entry.originalName === file.name &&
        entry.sizeBytes === file.size,
    );
    if (duplicate) {
      result.duplicates.push(structuredClone(duplicate.entry));
      continue;
    }
    const id = crypto.randomUUID();
    const url = URL.createObjectURL(file);
    const kind = mediaKind(file);
    const entry: NotebookMediaEntry = {
      id,
      canvasId,
      canvasTitle: "Notebook",
      originalName: file.name,
      mimeType: file.type || "application/octet-stream",
      kind,
      sizeBytes: file.size,
      width: null,
      height: null,
      hasThumbnail: kind === "image",
      hasProxy: false,
      createdAt: Date.now(),
    };
    browserMedia.set(id, { entry, url });
    result.imported.push(structuredClone(entry));
  }
  return result;
}

export function notebookMediaUrl(
  id: string,
  variant: "content" | "thumbnail" | "proxy" = "content",
): string {
  if (isTauri) return `media://localhost/${encodeURIComponent(id)}/${variant}`;
  return browserMedia.get(id)?.url ?? "";
}

export const notebookMediaData = {
  async list(query: NotebookMediaQuery = {}): Promise<NotebookMediaPage> {
    if (isTauri)
      return invoke("list_notebook_media", {
        query: { ...query, canvasType: "notebook", limit: query.limit ?? 60 },
      });
    const normalized = query.query?.trim().toLocaleLowerCase();
    let items = [...browserMedia.values()]
      .map(({ entry }) => structuredClone(entry))
      .filter(
        (entry) =>
          (!query.canvasId || entry.canvasId === query.canvasId) &&
          (!query.kind || entry.kind === query.kind) &&
          (!normalized ||
            `${entry.originalName} ${entry.canvasTitle} ${entry.mimeType}`
              .toLocaleLowerCase()
              .includes(normalized)),
      )
      .sort(
        (left, right) =>
          right.createdAt - left.createdAt || right.id.localeCompare(left.id),
      );
    if (query.cursor)
      items = items.filter(
        (entry) =>
          entry.createdAt < query.cursor!.createdAt ||
          (entry.createdAt === query.cursor!.createdAt &&
            entry.id < query.cursor!.id),
      );
    const limit = query.limit ?? 60;
    const page = items.slice(0, limit);
    const last = page.at(-1);
    return {
      items: page,
      nextCursor:
        items.length > limit && last
          ? { createdAt: last.createdAt, id: last.id }
          : null,
    };
  },
  async chooseAndImport(canvasId: string): Promise<NotebookMediaImportResult> {
    if (isTauri) {
      const chosen = await openDialog({ multiple: true, directory: false });
      const sourcePaths = !chosen
        ? []
        : Array.isArray(chosen)
          ? chosen
          : [chosen];
      if (!sourcePaths.length)
        return { imported: [], duplicates: [], failures: [] };
      return invoke("import_notebook_media_paths", { canvasId, sourcePaths });
    }
    return browserImport(canvasId, await chooseBrowserFiles());
  },
  async get(id: string): Promise<NotebookMediaEntry | null> {
    if (isTauri) return invoke("get_notebook_media", { id });
    const value = browserMedia.get(id)?.entry;
    return value ? structuredClone(value) : null;
  },
  async delete(id: string): Promise<boolean> {
    if (isTauri) return invoke("delete_notebook_media", { id });
    const value = browserMedia.get(id);
    if (value?.url.startsWith("blob:")) URL.revokeObjectURL(value.url);
    return browserMedia.delete(id);
  },
  async open(id: string): Promise<void> {
    if (isTauri) return invoke("open_notebook_media", { id });
    window.open(notebookMediaUrl(id), "_blank", "noopener,noreferrer");
  },
  async reveal(id: string): Promise<void> {
    if (isTauri) return invoke("reveal_notebook_media", { id });
    window.open(notebookMediaUrl(id), "_blank", "noopener,noreferrer");
  },
};

export async function readNativeClipboardImage(): Promise<CardPluginImageInput | null> {
  if (!isTauri) return null;
  const { readImage } = await import("@tauri-apps/plugin-clipboard-manager");
  const image = await readImage();
  try {
    const [rgba, size] = await Promise.all([image.rgba(), image.size()]);
    const codec = new ClipboardImageCodec();
    return {
      dataUrl: codec.encodePngDataUrl({
        rgba,
        width: size.width,
        height: size.height,
      }),
      name: "pasted-book-cover.png",
      mimeType: "image/png",
      width: size.width,
      height: size.height,
    };
  } finally {
    await image.close();
  }
}

export async function importNotebookImage(
  notebookId: string,
  input: CardPluginImageInput,
): Promise<CardPluginMediaAsset> {
  if (!input.mimeType.startsWith("image/"))
    throw new Error("Only image files can be used for a card cover.");
  if (!isTauri) {
    const duplicate = [...browserMedia.values()].find(
      ({ entry, url }) =>
        entry.canvasId === notebookId && url === input.dataUrl,
    );
    const id = duplicate?.entry.id ?? crypto.randomUUID();
    if (!duplicate) {
      browserMedia.set(id, {
        url: input.dataUrl,
        entry: {
          id,
          canvasId: notebookId,
          canvasTitle: "Notebook",
          originalName: input.name,
          mimeType: input.mimeType,
          kind: "image",
          sizeBytes: Math.max(0, Math.floor((input.dataUrl.length * 3) / 4)),
          width: input.width,
          height: input.height,
          hasThumbnail: true,
          hasProxy: false,
          createdAt: Date.now(),
        },
      });
    }
    return {
      id,
      name: input.name,
      mimeType: input.mimeType,
      width: input.width,
      height: input.height,
      url: input.dataUrl,
    };
  }
  const result = await invoke<NotebookMediaImportResult>(
    "import_notebook_media",
    {
      input: {
        canvasId: notebookId,
        originalName: input.name,
        mimeType: input.mimeType,
        dataUrl: input.dataUrl,
      },
    },
  );
  const entry = result.imported[0] ?? result.duplicates[0];
  if (!entry)
    throw new Error(
      result.failures[0]?.message ?? "The cover image could not be imported.",
    );
  return {
    id: entry.id,
    name: entry.originalName,
    mimeType: entry.mimeType,
    width: entry.width ?? input.width,
    height: entry.height ?? input.height,
    url: notebookMediaUrl(entry.id),
  };
}
