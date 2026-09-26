import * as React from "react";
import {
  WorkspaceMediaLibrary,
  type WorkspaceMediaItem,
  type WorkspaceMediaKind,
} from "@productivity-os/shared-ui/components/workspace-media-library";
import { WorkspaceMediaPreviewDialog } from "@productivity-os/shared-ui/components/workspace-media-preview-dialog";
import { toast } from "@productivity-os/shared-ui/hooks/use-toast";

import type { NotebookSummary } from "@/api/notebook-data";
import {
  notebookMediaData,
  notebookMediaUrl,
  type NotebookMediaCursor,
  type NotebookMediaEntry,
  type NotebookMediaKind,
} from "@/api/notebook-media";

function asWorkspaceItem(
  entry: NotebookMediaEntry,
  notebooks: readonly NotebookSummary[],
): WorkspaceMediaItem {
  const owner = notebooks.find((notebook) => notebook.id === entry.canvasId);
  return {
    id: entry.id,
    ownerId: entry.canvasId,
    ownerTitle: owner?.title ?? entry.canvasTitle,
    name: entry.originalName,
    mimeType: entry.mimeType,
    kind: entry.kind,
    sizeBytes: entry.sizeBytes,
    previewUrl: entry.hasThumbnail
      ? notebookMediaUrl(entry.id, "thumbnail")
      : entry.kind === "image"
        ? notebookMediaUrl(entry.id)
        : null,
    contentUrl: notebookMediaUrl(entry.id),
  };
}

export function Media({
  notebooks,
}: {
  notebooks: readonly NotebookSummary[];
}) {
  const [search, setSearch] = React.useState("");
  const [notebookFilter, setNotebookFilter] = React.useState("all");
  const [kindFilter, setKindFilter] = React.useState<
    "all" | WorkspaceMediaKind
  >("all");
  const [importNotebookId, setImportNotebookId] = React.useState(
    notebooks[0]?.id ?? "",
  );
  const [items, setItems] = React.useState<NotebookMediaEntry[]>([]);
  const [nextCursor, setNextCursor] =
    React.useState<NotebookMediaCursor | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [importing, setImporting] = React.useState(false);
  const [previewItem, setPreviewItem] =
    React.useState<WorkspaceMediaItem | null>(null);

  React.useEffect(() => {
    if (!importNotebookId && notebooks[0]) setImportNotebookId(notebooks[0].id);
  }, [importNotebookId, notebooks]);

  const load = React.useCallback(
    async (cursor: NotebookMediaCursor | null = null) => {
      setLoading(true);
      try {
        const page = await notebookMediaData.list({
          canvasId: notebookFilter === "all" ? null : notebookFilter,
          kind: kindFilter === "all" ? null : (kindFilter as NotebookMediaKind),
          query: search || null,
          cursor,
          limit: 60,
        });
        setItems((current) =>
          cursor ? [...current, ...page.items] : page.items,
        );
        setNextCursor(page.nextCursor);
      } catch (error) {
        toast({
          title: "Couldn’t load media",
          description: error instanceof Error ? error.message : String(error),
        });
      } finally {
        setLoading(false);
      }
    },
    [kindFilter, notebookFilter, search],
  );

  React.useEffect(() => {
    const timer = window.setTimeout(() => void load(), 180);
    return () => window.clearTimeout(timer);
  }, [load]);

  const importFiles = async () => {
    if (!importNotebookId) return;
    setImporting(true);
    try {
      const result = await notebookMediaData.chooseAndImport(importNotebookId);
      if (result.imported.length) {
        toast({
          title: `${result.imported.length} file${result.imported.length === 1 ? "" : "s"} added`,
        });
        await load();
      } else if (result.duplicates.length) {
        toast({
          title: "Already in this notebook",
          description: `${result.duplicates.length} duplicate file${result.duplicates.length === 1 ? " was" : "s were"} skipped.`,
        });
      }
      if (result.failures[0])
        toast({
          title: "Some files couldn’t be added",
          description: result.failures[0].message,
        });
    } catch (error) {
      toast({
        title: "Import failed",
        description: error instanceof Error ? error.message : String(error),
      });
    } finally {
      setImporting(false);
    }
  };

  const workspaceItems = items.map((entry) =>
    asWorkspaceItem(entry, notebooks),
  );
  return (
    <>
      <WorkspaceMediaLibrary
        items={workspaceItems}
        owners={notebooks.map((notebook) => ({
          id: notebook.id,
          title: notebook.title,
        }))}
        ownerNoun="notebook"
        description="Files stored by your notebooks"
        search={search}
        ownerFilter={notebookFilter}
        kindFilter={kindFilter}
        importOwnerId={importNotebookId}
        loading={loading}
        importing={importing}
        hasMore={Boolean(nextCursor)}
        onSearchChange={setSearch}
        onOwnerFilterChange={setNotebookFilter}
        onKindFilterChange={setKindFilter}
        onImportOwnerChange={setImportNotebookId}
        onImport={importFiles}
        onLoadMore={() => load(nextCursor)}
        onPreview={setPreviewItem}
        onOpen={(item) => notebookMediaData.open(item.id)}
        onReveal={(item) => notebookMediaData.reveal(item.id)}
        onDelete={async (item) => {
          await notebookMediaData.delete(item.id);
          setItems((current) =>
            current.filter((entry) => entry.id !== item.id),
          );
          setPreviewItem((current) =>
            current?.id === item.id ? null : current,
          );
        }}
      />
      <WorkspaceMediaPreviewDialog
        item={previewItem}
        onOpenChange={(open) => {
          if (!open) setPreviewItem(null);
        }}
        onOpenExternally={(item) => void notebookMediaData.open(item.id)}
      />
    </>
  );
}
