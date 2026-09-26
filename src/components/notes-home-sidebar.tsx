import * as React from "react";
import {
  Archive,
  Boxes,
  Clock3,
  Cog,
  FileClock,
  Folder,
  Image,
  Plus,
  Star,
  Trash2,
} from "lucide-react";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@productivity-os/shared-ui/components/ui/dialog";
import { Input } from "@productivity-os/shared-ui/components/ui/input";
import { SidebarSeparator } from "@productivity-os/shared-ui/components/ui/sidebar";
import {
  WorkspaceSidebar,
  WorkspaceSidebarFooterItem,
  WorkspaceSidebarSection,
  type WorkspaceSidebarItemDefinition,
} from "@productivity-os/shared-ui/components/workspace-sidebar";
import type { NotebookSummary } from "@/api/notebook-data";

type Props = {
  loading: boolean;
  search: string;
  activeItem: string;
  folders: readonly string[];
  starredNotebooks: readonly NotebookSummary[];
  onSearchChange(value: string): void;
  onActiveItemChange(item: string): void;
  onCreateFolder(name: string): void;
  onOpenNotebook(notebook: NotebookSummary): void;
};

const profiles = [
  { id: "personal", name: "Mustafa’s space", detail: "Personal workspace" },
  { id: "product", name: "Product team", detail: "Product workspace" },
  { id: "research", name: "Research team", detail: "Research workspace" },
] as const;

export function NotesHomeSidebar({
  loading,
  search,
  activeItem,
  folders,
  starredNotebooks,
  onSearchChange,
  onActiveItemChange,
  onCreateFolder,
  onOpenNotebook,
}: Props) {
  const [profileId, setProfileId] =
    React.useState<(typeof profiles)[number]["id"]>("personal");
  const [folderDialogOpen, setFolderDialogOpen] = React.useState(false);
  const [folderName, setFolderName] = React.useState("");
  const [folderError, setFolderError] = React.useState("");
  const libraryItems: WorkspaceSidebarItemDefinition[] = [
    { id: "recents", label: "Recents", icon: <Clock3 /> },
    { id: "drafts", label: "Drafts", icon: <FileClock /> },
  ];
  const folderItems: WorkspaceSidebarItemDefinition[] = folders.map(
    (folder) => ({ id: `folder:${folder}`, label: folder, icon: <Folder /> }),
  );
  const createFolder = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const name = folderName.trim();
    if (!name) return;
    if (
      folders.some(
        (folder) => folder.toLocaleLowerCase() === name.toLocaleLowerCase(),
      )
    ) {
      setFolderError("A folder with this name already exists.");
      return;
    }
    onCreateFolder(name);
    onActiveItemChange(`folder:${name}`);
    setFolderDialogOpen(false);
  };

  return (
    <>
      <WorkspaceSidebar
        profiles={profiles}
        activeProfileId={profileId}
        onProfileChange={(id) =>
          setProfileId(id as (typeof profiles)[number]["id"])
        }
        search={search}
        onSearchChange={onSearchChange}
        searchLabel="Search notebooks"
        style={{ "--workspace-accent": "#3b82f6" } as React.CSSProperties}
        footer={
          <WorkspaceSidebarFooterItem
            label="Settings"
            icon={<Cog />}
            active={activeItem === "settings"}
            onSelect={() => onActiveItemChange("settings")}
          />
        }
      >
        <WorkspaceSidebarSection
          items={libraryItems}
          activeItemId={activeItem}
          loading={loading}
          skeletonCount={2}
          onSelectItem={onActiveItemChange}
        />
        <SidebarSeparator />
        <WorkspaceSidebarSection
          label="Folders"
          items={folderItems}
          activeItemId={activeItem}
          loading={loading}
          onSelectItem={onActiveItemChange}
          className="workspace-folders-group"
          action={{
            label: "Create folder",
            icon: <Plus />,
            onSelect: () => {
              setFolderName("");
              setFolderError("");
              setFolderDialogOpen(true);
            },
          }}
        />
        <WorkspaceSidebarSection
          items={[
            { id: "media", label: "Media", icon: <Image /> },
            { id: "plugins", label: "Plugin Marketplace", icon: <Boxes /> },
            { id: "archive", label: "Archive", icon: <Archive /> },
            { id: "trash", label: "Trash", icon: <Trash2 /> },
          ]}
          activeItemId={activeItem}
          onSelectItem={onActiveItemChange}
        />
        <SidebarSeparator />
        <WorkspaceSidebarSection
          label="Starred"
          items={starredNotebooks.map((notebook) => ({
            id: `starred:${notebook.id}`,
            label: notebook.title,
            icon: <Star fill="currentColor" />,
            onSelect: () => onOpenNotebook(notebook),
          }))}
          loading={loading}
          emptyText="Star a notebook to keep it close."
        />
      </WorkspaceSidebar>
      <Dialog open={folderDialogOpen} onOpenChange={setFolderDialogOpen}>
        <DialogContent>
          <form className="grid gap-4" onSubmit={createFolder}>
            <DialogHeader>
              <DialogTitle>Create folder</DialogTitle>
              <DialogDescription>
                Add a folder to organize your notebooks.
              </DialogDescription>
            </DialogHeader>
            <label className="grid gap-1.5 text-xs text-muted-foreground">
              Folder name
              <Input
                autoFocus
                value={folderName}
                aria-invalid={Boolean(folderError)}
                onChange={(event) => {
                  setFolderName(event.currentTarget.value);
                  setFolderError("");
                }}
              />
              {folderError && (
                <span className="text-destructive">{folderError}</span>
              )}
            </label>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline">
                  Cancel
                </Button>
              </DialogClose>
              <Button type="submit" disabled={!folderName.trim()}>
                Create folder
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
