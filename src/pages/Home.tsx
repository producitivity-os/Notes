import { useCallback, useEffect, useMemo, useState } from "react"
import {
  BookOpen,
  BrainCircuit,
  ImagePlus,
  PencilLine,
  Trash2,
} from "@productivity-os/shared-ui/components/sf-symbols"
import { Button } from "@productivity-os/shared-ui/components/ui/button"
import {
  ApplicationSidebarContent,
  ApplicationSidebarLayout,
} from "@productivity-os/shared-ui/components/application-sidebar"
import { ApplicationContextMenu } from "@productivity-os/shared-ui/components/application-context-menu"
import {
  WorkspaceLibraryEmpty,
  WorkspaceLibraryHeading,
  WorkspaceLibrarySkeletonGrid,
  WorkspaceLibraryToolbar,
  WorkspacePreviewCard,
  type WorkspaceLibraryItem,
} from "@productivity-os/shared-ui/components/workspace-library"
import { notebookData, pluginData, type NotebookSummary } from "@/api/notebook-data"
import { NotesHomeSidebar } from "@/components/notes-home-sidebar"
import { BookCoverInput } from "@/components/book-cover-input"
import { importNotebookImage, notebookMediaUrl } from "@/api/notebook-media"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@productivity-os/shared-ui/components/ui/dialog"
import { Media } from "@/pages/Media"
import { notesPlugins } from "@/plugins/plugin-registry"

const libraryPages = new Set(["recents", "drafts", "archive", "trash"])

function relativeEdit(updatedAt: number): string {
  if (!updatedAt) return "Edited recently"
  const days = Math.round((updatedAt - Date.now()) / 86_400_000)
  if (Math.abs(days) < 1) return "Edited today"
  return `Edited ${new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(days, "day")}`
}

function filterLabel(activeItem: string): string {
  if (activeItem === "recents") return "Recent notebooks"
  if (activeItem === "drafts") return "Drafts"
  if (activeItem === "archive") return "Archive"
  if (activeItem === "trash") return "Trash"
  if (activeItem === "media") return "Media"
  if (activeItem.startsWith("folder:")) return activeItem.slice("folder:".length)
  return "Notebooks"
}

export function Home() {
  const [notebooks, setNotebooks] = useState<NotebookSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [activeItem, setActiveItem] = useState("recents")
  const [query, setQuery] = useState("")
  const [compact, setCompact] = useState(false)
  const [sortBy, setSortBy] = useState<"recent" | "title">("recent")
  const [extraFolders, setExtraFolders] = useState<string[]>([])
  const [renamingId, setRenamingId] = useState<string | null>(null)
  const [pluginVersion, setPluginVersion] = useState(0)
  const [coverNotebook, setCoverNotebook] = useState<NotebookSummary | null>(null)

  const refreshPlugins = useCallback(async () => {
    const installations = await pluginData.list()
    notesPlugins.setInstallations(
      installations.filter((item) => item.installed).map((item) => item.pluginId),
    )
    setPluginVersion((value) => value + 1)
  }, [])
  const refresh = useCallback(async () => {
    try {
      setNotebooks(await notebookData.list())
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refresh()
    void refreshPlugins()
  }, [refresh, refreshPlugins])
  useEffect(() => {
    void notebookData.initialNavigation().then(async (target) => {
      if (!target) return
      const notebook = await notebookData.get(target.notebookId)
      if (notebook)
        await notebookData.open(notebook.id, notebook.title, target.objectId)
    })
  }, [])
  useEffect(() => {
    let unlisten: undefined | (() => void)
    const browserRefresh = () => {
      void refreshPlugins()
    }
    window.addEventListener("notes:plugins-changed", browserRefresh)
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:plugins-changed", browserRefresh))
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => {
      unlisten?.()
      window.removeEventListener("notes:plugins-changed", browserRefresh)
    }
  }, [refreshPlugins])
  useEffect(() => {
    let unlisten: (() => void) | undefined
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:notebooks-changed", () => void refresh()))
      .then((dispose) => {
        unlisten = dispose
      })
      .catch(() => undefined)
    return () => unlisten?.()
  }, [refresh])

  const folders = useMemo(
    () =>
      [
        ...new Set([
          ...notebooks
            .map((item) => item.project)
            .filter((folder) => folder && folder !== "Drafts"),
          ...extraFolders,
        ]),
      ].sort(),
    [extraFolders, notebooks],
  )
  const page =
    activeItem === "plugins" || activeItem === "media"
      ? activeItem
      : "library"
  const title = filterLabel(activeItem)
  const visibleNotebooks = useMemo(() => {
    let result =
      activeItem === "drafts"
        ? notebooks.filter((notebook) => notebook.project === "Drafts")
        : activeItem.startsWith("folder:")
          ? notebooks.filter(
              (notebook) => notebook.project === activeItem.slice("folder:".length),
            )
          : activeItem === "archive" || activeItem === "trash"
            ? []
            : [...notebooks]
    const normalized = query.trim().toLocaleLowerCase()
    if (normalized)
      result = result.filter((notebook) =>
        `${notebook.title} ${notebook.project}`
          .toLocaleLowerCase()
          .includes(normalized),
      )
    return result.sort(
      sortBy === "title"
        ? (a, b) => a.title.localeCompare(b.title)
        : (a, b) => b.updatedAt - a.updatedAt,
    )
  }, [activeItem, notebooks, query, sortBy])

  const createNotebook = async () => {
    const id = crypto.randomUUID()
    const notebookTitle = `Untitled notebook ${notebooks.length + 1}`
    const project = activeItem.startsWith("folder:")
      ? activeItem.slice("folder:".length)
      : activeItem === "drafts"
        ? "Drafts"
        : "My notebooks"
    await notebookData.save({
      id,
      title: notebookTitle,
      project,
      canvasType: "notebook",
      icon: "file-text",
      starred: false,
      coverMediaId: null,
      expectedRevision: null,
      canvas: {
        schemaVersion: 6,
        activeLayerId: "main",
        focusedLayerId: null,
        unfocusedLayerOpacity: 0.25,
        viewport: { x: 0, y: 0, scale: 1 },
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
        objects: [],
      },
    })
    await refresh()
    await notebookData.open(id, notebookTitle)
  }
  const setStarred = async (notebook: NotebookSummary) => {
    await notebookData.update(notebook.id, { starred: !notebook.starred })
    await refresh()
  }
  const rename = async (notebook: NotebookSummary, nextTitle: string) => {
    setRenamingId(null)
    if (nextTitle !== notebook.title)
      await notebookData.update(notebook.id, { title: nextTitle })
    await refresh()
  }
  const remove = async (notebook: NotebookSummary) => {
    if (!window.confirm(`Delete “${notebook.title}”?`)) return
    await notebookData.delete(notebook.id)
    await refresh()
  }
  const asLibraryItem = (notebook: NotebookSummary): WorkspaceLibraryItem => ({
    id: notebook.id,
    title: notebook.title,
    subtitle: relativeEdit(notebook.updatedAt),
    icon: notebook.icon || "file-text",
    previewUrl: notebook.coverMediaId
      ? notebookMediaUrl(notebook.coverMediaId, "thumbnail")
      : notebook.previewDataUrl,
    draft: notebook.project === "Drafts",
  })
  return (
    <ApplicationSidebarLayout
      className="notes-home-shell"
      accentColor="#3b82f6"
    >
      <NotesHomeSidebar
            loading={loading}
            search={query}
            activeItem={activeItem}
            folders={folders}
            starredNotebooks={notebooks.filter((item) => item.starred)}
            onSearchChange={setQuery}
            onActiveItemChange={(item) => {
              setActiveItem(item)
              if (
                !libraryPages.has(item) &&
                !item.startsWith("folder:") &&
                !["plugins", "media"].includes(item)
              )
                setActiveItem("recents")
            }}
            onCreateFolder={(folder) =>
              setExtraFolders((current) => [...current, folder])
            }
            onOpenNotebook={(notebook) =>
              void notebookData.open(notebook.id, notebook.title)
            }
      />
      <ApplicationSidebarContent className="workspace-library-main">
            {page === "library" ? (
              <>
                <WorkspaceLibraryToolbar
                  title={title}
                  description={
                    query
                      ? `${visibleNotebooks.length} matching notebooks`
                      : activeItem === "recents"
                        ? "Pick up where you left off"
                        : `${visibleNotebooks.length} notebooks`
                  }
                  showSidebarTrigger={false}
                  compact={compact}
                  createLabel="New notebook"
                  itemLabel="notebooks"
                  onSort={() =>
                    setSortBy((value) => (value === "recent" ? "title" : "recent"))
                  }
                  onCompactChange={setCompact}
                  onCreate={() => void createNotebook()}
                />
                <section className="workspace-library-content" aria-busy={loading}>
                  {loading ? (
                    <WorkspaceLibrarySkeletonGrid />
                  ) : visibleNotebooks.length ? (
                    <div
                      className={`workspace-library-card-grid${compact ? " compact" : ""}`}
                    >
                      {visibleNotebooks.map((notebook) => (
                        <ApplicationContextMenu
                          key={notebook.id}
                          actions={[
                            {
                              id: "open",
                              label: "Open",
                              icon: <BookOpen aria-hidden="true" />,
                              onSelect: () =>
                                notebookData.open(notebook.id, notebook.title),
                            },
                            {
                              id: "review",
                              label: "Review",
                              icon: <BrainCircuit aria-hidden="true" />,
                              onSelect: () => notebookData.revise(notebook.id),
                            },
                            {
                              id: "rename",
                              label: "Rename",
                              icon: <PencilLine aria-hidden="true" />,
                              onSelect: () => setRenamingId(notebook.id),
                            },
                            {
                              id: "cover",
                              label: notebook.coverMediaId
                                ? "Replace cover"
                                : "Set cover",
                              icon: <ImagePlus aria-hidden="true" />,
                              onSelect: () => setCoverNotebook(notebook),
                            },
                            ...(notebook.coverMediaId
                              ? [
                                  {
                                    id: "clear-cover",
                                    label: "Clear cover",
                                    onSelect: () =>
                                      notebookData
                                        .update(notebook.id, {
                                          coverMediaId: null,
                                        })
                                        .then(refresh),
                                  },
                                ]
                              : []),
                            { id: "delete-separator", type: "separator" },
                            {
                              id: "delete",
                              label: "Delete",
                              icon: <Trash2 aria-hidden="true" />,
                              variant: "destructive",
                              onSelect: () => remove(notebook),
                            },
                          ]}
                        >
                          <WorkspacePreviewCard
                            item={asLibraryItem(notebook)}
                            itemNoun="notebook"
                            starred={notebook.starred}
                            renaming={renamingId === notebook.id}
                            onOpen={() =>
                              void notebookData.open(notebook.id, notebook.title)
                            }
                            onStarToggle={() => void setStarred(notebook)}
                            onRenameCommit={(nextTitle) =>
                              void rename(notebook, nextTitle)
                            }
                            onRenameCancel={() => setRenamingId(null)}
                          />
                        </ApplicationContextMenu>
                      ))}
                    </div>
                  ) : (
                    <WorkspaceLibraryEmpty
                      noun="notebooks"
                      searched={Boolean(query)}
                      onClearSearch={() => setQuery("")}
                    />
                  )}
                </section>
              </>
            ) : page === "media" ? (
              <Media notebooks={notebooks} />
            ) : page === "plugins" ? (
              <section className="notes-library-page">
                <WorkspaceLibraryHeading
                  title="Plugin Marketplace"
                  description="Installed plugins are available in every notebook."
                />
                <div className="notes-market-grid" data-version={pluginVersion}>
                  {notesPlugins.marketplace().map((plugin) => {
                    const installed = notesPlugins.isInstalled(plugin.manifest.id)
                    return (
                      <article key={plugin.manifest.id}>
                        <span className="notes-plugin-icon">◇</span>
                        <div>
                          <h2>{plugin.manifest.name}</h2>
                          <p>{plugin.manifest.description}</p>
                          <small>
                            {plugin.manifest.author} · v{plugin.manifest.version}
                          </small>
                        </div>
                        <Button
                          type="button"
                          variant={installed ? "outline" : "default"}
                          size="sm"
                          onClick={() =>
                            void (async () => {
                              await pluginData.setInstalled(
                                plugin.manifest.id,
                                !installed,
                              )
                              await (installed
                                ? plugin.lifecycle.onUninstall?.({})
                                : plugin.lifecycle.onInstall?.({}))
                              await refreshPlugins()
                            })()
                          }
                        >
                          {installed ? "Uninstall" : "Install"}
                        </Button>
                      </article>
                    )
                  })}
                </div>
              </section>
            ) : null}
      </ApplicationSidebarContent>
      <Dialog
        open={Boolean(coverNotebook)}
        onOpenChange={(open) => !open && setCoverNotebook(null)}
      >
        <DialogContent className="notebook-cover-dialog">
          <DialogHeader>
            <DialogTitle>Notebook cover</DialogTitle>
            <DialogDescription>
              Upload an image or focus the preview and paste from the clipboard.
            </DialogDescription>
          </DialogHeader>
          {coverNotebook && (
            <BookCoverInput
              ariaLabel="Notebook cover image input"
              currentUrl={
                coverNotebook.coverMediaId
                  ? notebookMediaUrl(coverNotebook.coverMediaId, "thumbnail")
                  : null
              }
              value={null}
              removed={false}
              onChange={async (value) => {
                if (!value) return
                const media = await importNotebookImage(coverNotebook.id, value)
                await notebookData.update(coverNotebook.id, {
                  coverMediaId: media.id,
                })
                await refresh()
                setCoverNotebook(null)
              }}
              onRemove={() => {
                void notebookData
                  .update(coverNotebook.id, { coverMediaId: null })
                  .then(refresh)
                setCoverNotebook(null)
              }}
            />
          )}
        </DialogContent>
      </Dialog>
    </ApplicationSidebarLayout>
  )
}
