import { useState } from "react";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@productivity-os/shared-ui/components/ui/dialog";
import type {
  CardPluginDefinition,
  CardPluginFieldErrors,
  CardPluginHostServices,
} from "@/plugins/plugin-api";

type Props = {
  plugin: CardPluginDefinition<any, any>;
  mode: "create" | "edit";
  initialData: unknown;
  services: CardPluginHostServices;
  onSave(data: Record<string, unknown>): void;
  onCancel(): void;
};

export function CardEditorDialog({
  plugin,
  mode,
  initialData,
  services,
  onSave,
  onCancel,
}: Props) {
  const editor = plugin.slots.Editor!;
  const [draft, setDraft] = useState(() =>
    editor.createDraft(plugin.hydrate(initialData)),
  );
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<CardPluginFieldErrors>({});
  const [saving, setSaving] = useState(false);
  const Editor = editor.Component;

  const save = async () => {
    const result = editor.schema.safeParse(draft);
    if (!result.success) {
      const nextErrors: CardPluginFieldErrors = {};
      for (const issue of result.error.issues) {
        const field = String(issue.path[0] ?? "_form");
        (nextErrors[field] ??= []).push(issue.message);
      }
      setFieldErrors(nextErrors);
      setError(nextErrors._form?.[0] ?? null);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const data = await editor.commit(result.data, services);
      onSave(plugin.serialize(data));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => !open && !saving && onCancel()}>
      <DialogContent
        className="card-editor-dialog"
        showCloseButton={false}
        onEscapeKeyDown={(event) => saving && event.preventDefault()}
        onKeyDown={(event) => {
          if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
            event.preventDefault();
            if (!saving) void save();
          }
        }}
      >
        <DialogHeader className="sr-only">
          <DialogTitle>
            {mode === "create"
              ? `New ${plugin.manifest.name}`
              : `Edit ${plugin.manifest.name}`}
          </DialogTitle>
          <DialogDescription>{plugin.manifest.description}</DialogDescription>
        </DialogHeader>
        <Editor
          mode={mode}
          draft={draft}
          onChange={(next) => {
            setDraft(next);
            setError(null);
            setFieldErrors({});
          }}
          services={services}
          fieldErrors={fieldErrors}
        />
        {error && <p className="card-editor-error">{error}</p>}
        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            disabled={saving}
            onClick={onCancel}
          >
            Cancel <kbd>Esc</kbd>
          </Button>
          <Button type="button" disabled={saving} onClick={() => void save()}>
            {saving ? (
              "Saving…"
            ) : (
              <>
                Save <kbd>⌘↵</kbd>
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
