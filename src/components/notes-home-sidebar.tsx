import * as React from "react";
import {
  Archive,
  Boxes,
  Clock3,
  FileClock,
  Folder,
  Image,
  Plus,
  Star,
  Trash2,
} from "@productivity-os/shared-ui/components/sf-symbols";
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
import {
  ApplicationSidebar,
  ApplicationSidebarItem,
  ApplicationSidebarNav,
  ApplicationSidebarSection,
} from "@productivity-os/shared-ui/components/application-sidebar";
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
  const [folderDialogOpen, setFolderDialogOpen] = React.useState(false);
  const [folderName, setFolderName] = React.useState("");
  const [folderError, setFolderError] = React.useState("");
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
      <ApplicationSidebar
        search={{
          value: search,
          onChange: onSearchChange,
          placeholder: "Search notebooks",
        }}
      >
        <ApplicationSidebarNav>
          <ApplicationSidebarItem
            icon={<Clock3 />}
            label="Recents"
            active={activeItem === "recents"}
            onClick={() => onActiveItemChange("recents")}
          />
          <ApplicationSidebarItem
            icon={<FileClock />}
            label="Drafts"
            active={activeItem === "drafts"}
            onClick={() => onActiveItemChange("drafts")}
          />
        </ApplicationSidebarNav>
        <ApplicationSidebarSection
          label="Folders"
          action={
            <Button
              type="button"
              size="icon-xs"
              variant="ghost"
              aria-label="Create folder"
              onClick={() => {
                setFolderName("");
                setFolderError("");
                setFolderDialogOpen(true);
              }}
            >
              <Plus />
            </Button>
          }
        >
          {loading ? (
            <span className="application-sidebar-loading">Loading…</span>
          ) : (
            folders.map((folder) => (
              <ApplicationSidebarItem
                key={folder}
                icon={<Folder />}
                label={folder}
                active={activeItem === `folder:${folder}`}
                onClick={() => onActiveItemChange(`folder:${folder}`)}
              />
            ))
          )}
        </ApplicationSidebarSection>
        <ApplicationSidebarSection>
          <ApplicationSidebarItem
            icon={<Image />}
            label="Media"
            active={activeItem === "media"}
            onClick={() => onActiveItemChange("media")}
          />
          <ApplicationSidebarItem
            icon={<Boxes />}
            label="Plugin Marketplace"
            active={activeItem === "plugins"}
            onClick={() => onActiveItemChange("plugins")}
          />
          <ApplicationSidebarItem
            icon={<Archive />}
            label="Archive"
            active={activeItem === "archive"}
            onClick={() => onActiveItemChange("archive")}
          />
          <ApplicationSidebarItem
            icon={<Trash2 />}
            label="Trash"
            active={activeItem === "trash"}
            onClick={() => onActiveItemChange("trash")}
          />
        </ApplicationSidebarSection>
        <ApplicationSidebarSection label="Starred">
          {starredNotebooks.map((notebook) => (
            <ApplicationSidebarItem
              key={notebook.id}
              icon={<Star fill="currentColor" />}
              label={notebook.title}
              onClick={() => onOpenNotebook(notebook)}
            />
          ))}
          {!loading && starredNotebooks.length === 0 && (
            <span className="application-sidebar-empty">
              Star a notebook to keep it close.
            </span>
          )}
        </ApplicationSidebarSection>
      </ApplicationSidebar>
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
