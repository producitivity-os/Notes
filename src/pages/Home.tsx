import { useCallback, useEffect, useMemo, useState } from "react";
import {
  BookOpen,
  BrainCircuit,
  Monitor,
  Moon,
  PencilLine,
  Sun,
  Trash2,
} from "lucide-react";
import { WorkspaceAppHeader } from "@productivity-os/shared-ui/components/app-header";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import {
  useTheme,
  type Theme,
} from "@productivity-os/shared-ui/components/theme-provider";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@productivity-os/shared-ui/components/ui/context-menu";
import {
  WorkspaceLibraryEmpty,
  WorkspaceLibraryHeading,
  WorkspaceLibraryMain,
  WorkspaceLibraryShell,
  WorkspaceLibrarySkeletonGrid,
  WorkspaceLibraryToolbar,
  WorkspacePreviewCard,
  type WorkspaceLibraryItem,
} from "@productivity-os/shared-ui/components/workspace-library";
import {
  notebookData,
  pluginData,
  type NotebookSummary,
} from "@/api/notebook-data";
import { NotesHomeSidebar } from "@/components/notes-home-sidebar";
import { Media } from "@/pages/Media";
import { notesPlugins } from "@/plugins/plugin-registry";

const libraryPages = new Set(["recents", "drafts", "archive", "trash"]);

function relativeEdit(updatedAt: number): string {
  if (!updatedAt) return "Edited recently";
  const days = Math.round((updatedAt - Date.now()) / 86_400_000);
  if (Math.abs(days) < 1) return "Edited today";
  return `Edited ${new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(days, "day")}`;
}

function filterLabel(activeItem: string): string {
  if (activeItem === "recents") return "Recent notebooks";
  if (activeItem === "drafts") return "Drafts";
  if (activeItem === "archive") return "Archive";
  if (activeItem === "trash") return "Trash";
  if (activeItem === "media") return "Media";
  if (activeItem.startsWith("folder:"))
    return activeItem.slice("folder:".length);
  return "Notebooks";
}

function breadcrumbLabel(activeItem: string): string {
  if (activeItem === "recents") return "Recents";
  if (activeItem === "drafts") return "Drafts";
  if (activeItem === "media") return "Media";
  if (activeItem === "plugins") return "Plugin Marketplace";
  if (activeItem === "archive") return "Archive";
  if (activeItem === "trash") return "Trash";
  if (activeItem === "settings") return "Settings";
  if (activeItem.startsWith("folder:"))
    return activeItem.slice("folder:".length);
  return "Recents";
}

export function Home() {
  const { theme, setTheme } = useTheme();
  const [notebooks, setNotebooks] = useState<NotebookSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeItem, setActiveItem] = useState("recents");
  const [query, setQuery] = useState("");
  const [compact, setCompact] = useState(false);
  const [sortBy, setSortBy] = useState<"recent" | "title">("recent");
  const [extraFolders, setExtraFolders] = useState<string[]>([]);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [pluginVersion, setPluginVersion] = useState(0);
  const [notificationCount, setNotificationCount] = useState(3);

  const refreshPlugins = useCallback(async () => {
    const installations = await pluginData.list();
    notesPlugins.setInstallations(
      installations
        .filter((item) => item.installed)
        .map((item) => item.pluginId),
    );
    setPluginVersion((value) => value + 1);
  }, []);
  const refresh = useCallback(async () => {
    try {
      setNotebooks(await notebookData.list());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    void refreshPlugins();
  }, [refresh, refreshPlugins]);
  useEffect(() => {
    void notebookData.initialNavigation().then(async (target) => {
      if (!target) return;
      const notebook = await notebookData.get(target.notebookId);
      if (notebook)
        await notebookData.open(notebook.id, notebook.title, target.objectId);
    });
  }, []);
  useEffect(() => {
    let unlisten: undefined | (() => void);
    const browserRefresh = () => {
      void refreshPlugins();
    };
    window.addEventListener("notes:plugins-changed", browserRefresh);
    void import("@tauri-apps/api/event")
      .then(({ listen }) => listen("notes:plugins-changed", browserRefresh))
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => {
      unlisten?.();
      window.removeEventListener("notes:plugins-changed", browserRefresh);
    };
  }, [refreshPlugins]);
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen("notes:notebooks-changed", () => void refresh()),
      )
      .then((dispose) => {
        unlisten = dispose;
      })
      .catch(() => undefined);
    return () => unlisten?.();
  }, [refresh]);

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
  );
  const page =
    activeItem === "plugins" ||
    activeItem === "settings" ||
    activeItem === "media"
      ? activeItem
      : "library";
  const title = filterLabel(activeItem);
  const visibleNotebooks = useMemo(() => {
    let result =
      activeItem === "drafts"
        ? notebooks.filter((notebook) => notebook.project === "Drafts")
        : activeItem.startsWith("folder:")
          ? notebooks.filter(
              (notebook) =>
                notebook.project === activeItem.slice("folder:".length),
            )
          : activeItem === "archive" || activeItem === "trash"
            ? []
            : [...notebooks];
    const normalized = query.trim().toLocaleLowerCase();
    if (normalized)
      result = result.filter((notebook) =>
        `${notebook.title} ${notebook.project}`
          .toLocaleLowerCase()
          .includes(normalized),
      );
    return result.sort(
      sortBy === "title"
        ? (a, b) => a.title.localeCompare(b.title)
        : (a, b) => b.updatedAt - a.updatedAt,
    );
  }, [activeItem, notebooks, query, sortBy]);

  const createNotebook = async () => {
    const id = crypto.randomUUID();
    const notebookTitle = `Untitled notebook ${notebooks.length + 1}`;
    const project = activeItem.startsWith("folder:")
      ? activeItem.slice("folder:".length)
      : activeItem === "drafts"
        ? "Drafts"
        : "My notebooks";
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
        schemaVersion: 5,
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
    });
    await refresh();
    await notebookData.open(id, notebookTitle);
  };
  const setStarred = async (notebook: NotebookSummary) => {
    await notebookData.update(notebook.id, { starred: !notebook.starred });
    await refresh();
  };
  const rename = async (notebook: NotebookSummary, nextTitle: string) => {
    setRenamingId(null);
    if (nextTitle !== notebook.title)
      await notebookData.update(notebook.id, { title: nextTitle });
    await refresh();
  };
  const remove = async (notebook: NotebookSummary) => {
    if (!window.confirm(`Delete “${notebook.title}”?`)) return;
    await notebookData.delete(notebook.id);
    await refresh();
  };
  const asLibraryItem = (notebook: NotebookSummary): WorkspaceLibraryItem => ({
    id: notebook.id,
    title: notebook.title,
    subtitle: relativeEdit(notebook.updatedAt),
    icon: notebook.icon || "file-text",
    previewUrl: notebook.previewDataUrl,
    draft: notebook.project === "Drafts",
  });
  const changeTheme = (nextTheme: Theme) => {
    setTheme(nextTheme);
    void import("@tauri-apps/api/event")
      .then(({ emit }) => emit("notes:theme-changed", nextTheme))
      .catch(() => undefined);
  };

  return (
    <div className="notes-home-shell">
      <WorkspaceAppHeader
        homeLabel="Notes home"
        homeActive
        onHomeSelect={() => setActiveItem("recents")}
        breadcrumbs={[
          {
            id: "home",
            label: "Home",
            onSelect: () => setActiveItem("recents"),
          },
          { id: activeItem, label: breadcrumbLabel(activeItem), current: true },
        ]}
        tabs={[]}
        onTabSelect={() => undefined}
        notificationLabel="Notifications"
        notificationCount={notificationCount}
        onNotificationsSelect={() => setNotificationCount(0)}
        menuLabel="Notes menu"
        menuItems={[
          {
            id: "plugins",
            label: "Plugin Marketplace",
            onSelect: () => setActiveItem("plugins"),
          },
          {
            id: "settings",
            label: "Settings",
            onSelect: () => setActiveItem("settings"),
          },
          { id: "about-separator", type: "separator" },
          { id: "about", label: "About Notes", disabled: true },
        ]}
      />
      <div className="notes-home-viewport">
        <WorkspaceLibraryShell>
          <NotesHomeSidebar
            loading={loading}
            search={query}
            activeItem={activeItem}
            folders={folders}
            starredNotebooks={notebooks.filter((item) => item.starred)}
            onSearchChange={setQuery}
            onActiveItemChange={(item) => {
              setActiveItem(item);
              if (
                !libraryPages.has(item) &&
                !item.startsWith("folder:") &&
                !["plugins", "settings", "media"].includes(item)
              )
                setActiveItem("recents");
            }}
            onCreateFolder={(folder) =>
              setExtraFolders((current) => [...current, folder])
            }
            onOpenNotebook={(notebook) =>
              void notebookData.open(notebook.id, notebook.title)
            }
          />
          <WorkspaceLibraryMain>
            {page === "library" ? (
              <>
                <WorkspaceLibraryToolbar
                  title={title}
                  compact={compact}
                  createLabel="New notebook"
                  itemLabel="notebooks"
                  onSort={() =>
                    setSortBy((value) =>
                      value === "recent" ? "title" : "recent",
                    )
                  }
                  onCompactChange={setCompact}
                  onCreate={() => void createNotebook()}
                />
                <section
                  className="workspace-library-content"
                  aria-busy={loading}
                >
                  <WorkspaceLibraryHeading
                    title={query ? "Search results" : title}
                    description={
                      query
                        ? `${visibleNotebooks.length} matching notebooks`
                        : activeItem === "recents"
                          ? "Pick up where you left off"
                          : `${visibleNotebooks.length} notebooks`
                    }
                  />
                  {loading ? (
                    <WorkspaceLibrarySkeletonGrid />
                  ) : visibleNotebooks.length ? (
                    <div
                      className={`workspace-library-card-grid${compact ? " compact" : ""}`}
                    >
                      {visibleNotebooks.map((notebook) => (
                        <ContextMenu key={notebook.id}>
                          <ContextMenuTrigger asChild>
                            <WorkspacePreviewCard
                              item={asLibraryItem(notebook)}
                              itemNoun="notebook"
                              starred={notebook.starred}
                              renaming={renamingId === notebook.id}
                              onOpen={() =>
                                void notebookData.open(
                                  notebook.id,
                                  notebook.title,
                                )
                              }
                              onStarToggle={() => void setStarred(notebook)}
                              onRenameCommit={(nextTitle) =>
                                void rename(notebook, nextTitle)
                              }
                              onRenameCancel={() => setRenamingId(null)}
                            />
                          </ContextMenuTrigger>
                          <ContextMenuContent>
                            <ContextMenuItem
                              onSelect={() =>
                                void notebookData.open(
                                  notebook.id,
                                  notebook.title,
                                )
                              }
                            >
                              <BookOpen aria-hidden="true" />
                              Open
                            </ContextMenuItem>
                            <ContextMenuItem
                              onSelect={() =>
                                void notebookData.revise(notebook.id)
                              }
                            >
                              <BrainCircuit aria-hidden="true" />
                              Review
                            </ContextMenuItem>
                            <ContextMenuItem
                              onSelect={() => setRenamingId(notebook.id)}
                            >
                              <PencilLine aria-hidden="true" />
                              Rename
                            </ContextMenuItem>
                            <ContextMenuSeparator />
                            <ContextMenuItem
                              variant="destructive"
                              onSelect={() => void remove(notebook)}
                            >
                              <Trash2 aria-hidden="true" />
                              Delete
                            </ContextMenuItem>
                          </ContextMenuContent>
                        </ContextMenu>
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
                    const installed = notesPlugins.isInstalled(
                      plugin.manifest.id,
                    );
                    return (
                      <article key={plugin.manifest.id}>
                        <span className="notes-plugin-icon">◇</span>
                        <div>
                          <h2>{plugin.manifest.name}</h2>
                          <p>{plugin.manifest.description}</p>
                          <small>
                            {plugin.manifest.author} · v
                            {plugin.manifest.version}
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
                              );
                              await (installed
                                ? plugin.lifecycle.onUninstall?.({})
                                : plugin.lifecycle.onInstall?.({}));
                              await refreshPlugins();
                            })()
                          }
                        >
                          {installed ? "Uninstall" : "Install"}
                        </Button>
                      </article>
                    );
                  })}
                </div>
              </section>
            ) : (
              <section className="notes-library-page">
                <WorkspaceLibraryHeading
                  title="Settings"
                  description="Configure your Notes workspace."
                />
                <div className="notes-settings-panel">
                  <span>
                    <strong>Appearance</strong>
                    <small>Choose how Notes looks in every open window.</small>
                  </span>
                  <div
                    className="notes-theme-options"
                    role="group"
                    aria-label="Theme"
                  >
                    {(
                      [
                        ["dark", "Dark", <Moon key="dark" />],
                        ["light", "Light", <Sun key="light" />],
                        ["system", "System", <Monitor key="system" />],
                      ] as const
                    ).map(([value, label, icon]) => (
                      <Button
                        key={value}
                        type="button"
                        variant={theme === value ? "default" : "outline"}
                        aria-pressed={theme === value}
                        onClick={() => changeTheme(value)}
                      >
                        {icon}
                        {label}
                      </Button>
                    ))}
                  </div>
                  <p>
                    Plugin installations apply globally to every notebook
                    window.
                  </p>
                </div>
              </section>
            )}
          </WorkspaceLibraryMain>
        </WorkspaceLibraryShell>
      </div>
    </div>
  );
}
