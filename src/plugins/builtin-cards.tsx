import { useEffect, useState } from "react";
import { BookOpen, NotebookTabs, UserRound } from "@productivity-os/shared-ui/components/sf-symbols";
import { z } from "zod";
import {
  IllustrationCard,
  ImageObject,
  RectangleObject,
  TextObject,
  type CanvasObject,
  type PluginCard,
} from "@productivity-os/canvas";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import { Input } from "@productivity-os/shared-ui/components/ui/input";
import { Textarea } from "@productivity-os/shared-ui/components/ui/textarea";
import { BookCoverInput } from "@/components/book-cover-input";
import { PersonInput } from "@/components/person-input";
import {
  createPluginCard,
  defineCardPlugin,
  type CardPluginEditorProps,
  type CardPluginImageInput,
} from "./plugin-api";

const text = (
  card: PluginCard,
  id: string,
  value: string,
  x: number,
  y: number,
  width: number,
  size: number,
  color = 0x172033,
  height = size * 3,
  lineHeight = Math.round(size * 1.35),
  maxLines?: number,
) =>
  new TextObject({
    id: `${card.id}-${id}`,
    layerId: card.layerId,
    type: "text",
    x,
    y,
    width,
    height,
    text: value,
    fontSize: size,
    lineHeight,
    maxLines,
    color,
    sizing: "fixed",
    weight: id === "title" ? "bold" : "regular",
  });

type BookData = Record<string, unknown> & {
  title: string;
  authorPersonId: string | null;
  authorName: string;
  description: string;
  coverMediaId: string | null;
  coverWidth: number | null;
  coverHeight: number | null;
};

type BookDraft = BookData & {
  coverInput: CardPluginImageInput | null;
  removeCover: boolean;
};

const normalizeBook = (value: unknown): BookData => {
  const data =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  return {
    title: typeof data.title === "string" ? data.title : "",
    authorPersonId:
      typeof data.authorPersonId === "string" ? data.authorPersonId : null,
    authorName:
      typeof data.authorName === "string"
        ? data.authorName
        : typeof data.author === "string"
          ? data.author
          : "",
    description:
      typeof data.description === "string"
        ? data.description
        : typeof data.notes === "string"
          ? data.notes
          : "",
    coverMediaId:
      typeof data.coverMediaId === "string" ? data.coverMediaId : null,
    coverWidth: typeof data.coverWidth === "number" ? data.coverWidth : null,
    coverHeight: typeof data.coverHeight === "number" ? data.coverHeight : null,
  };
};

const bookSchema = z
  .object({
    title: z.string().trim().min(1, "Enter a book title."),
    authorName: z.string().trim().min(1, "Choose or create an author."),
  })
  .passthrough() as unknown as z.ZodType<BookDraft>;

function FieldError({ messages }: { messages?: string[] }) {
  return messages?.[0] ? (
    <small className="card-editor-field-error">{messages[0]}</small>
  ) : null;
}

function BookEditor({
  draft,
  onChange,
  services,
  fieldErrors,
}: CardPluginEditorProps<BookDraft>) {
  const patch = (value: Partial<BookDraft>) => onChange({ ...draft, ...value });
  return (
    <div className="card-editor-form book-editor-form">
      <BookCoverInput
        currentUrl={
          draft.coverMediaId ? services.mediaUrl(draft.coverMediaId) : null
        }
        value={draft.coverInput}
        removed={draft.removeCover}
        onChange={(coverInput) => patch({ coverInput, removeCover: false })}
        onRemove={() => patch({ coverInput: null, removeCover: true })}
      />
      <div className="card-editor-fields">
        <label>
          Title
          <Input
            autoFocus
            value={draft.title}
            placeholder="Book title"
            aria-invalid={Boolean(fieldErrors.title)}
            onChange={(event) => patch({ title: event.currentTarget.value })}
          />
          <FieldError messages={fieldErrors.title} />
        </label>
        <label>
          Author
          <PersonInput
            personId={draft.authorPersonId}
            name={draft.authorName}
            services={services}
            invalid={Boolean(fieldErrors.authorName)}
            onChange={(authorPersonId, authorName) =>
              patch({ authorPersonId, authorName })
            }
          />
          <FieldError messages={fieldErrors.authorName} />
        </label>
        <label>
          Description
          <Textarea
            value={draft.description}
            placeholder="Description"
            onChange={(event) =>
              patch({ description: event.currentTarget.value })
            }
          />
        </label>
      </div>
    </div>
  );
}

function coverCrop(width: number | null, height: number | null) {
  if (!width || !height) return { x: 0, y: 0, width: 1, height: 1 };
  const sourceRatio = width / height;
  const targetRatio = 148 / 222;
  if (sourceRatio > targetRatio) {
    const cropWidth = targetRatio / sourceRatio;
    return { x: (1 - cropWidth) / 2, y: 0, width: cropWidth, height: 1 };
  }
  const cropHeight = sourceRatio / targetRatio;
  return { x: 0, y: (1 - cropHeight) / 2, width: 1, height: cropHeight };
}

export const bookCard = defineCardPlugin<BookData, BookDraft>({
  manifest: {
    id: "notes.book-card",
    name: "Book",
    description: "A book cover, title, author, and description.",
    version: "3.0.0",
    author: "Productivity OS",
    marketplace: false,
    card: {
      type: "book",
      schemaVersion: 3,
      defaultDimensions: { width: 172, height: 294 },
    },
  },
  propertiesPanel: "hidden",
  create(context) {
    return createPluginCard(this.manifest, context, normalizeBook(null));
  },
  hydrate: normalizeBook,
  serialize: normalizeBook,
  migrate: normalizeBook,
  slots: {
    ToolbarIcon: BookOpen,
    canvasRender(card, context) {
      const data = normalizeBook(card.pluginData);
      const cover = data.coverMediaId
        ? new ImageObject({
            id: `${card.id}-cover`,
            layerId: card.layerId,
            type: "image",
            x: 12,
            y: 12,
            width: 148,
            height: 222,
            rotation: 0,
            opacity: 1,
            src: context.mediaUrl(data.coverMediaId),
            previewSrc: context.mediaUrl(data.coverMediaId, "thumbnail"),
            sourceWidth: data.coverWidth ?? undefined,
            sourceHeight: data.coverHeight ?? undefined,
            crop: coverCrop(data.coverWidth, data.coverHeight),
            cornerRadius: 5,
            lockAspectRatio: true,
          })
        : new RectangleObject({
            id: `${card.id}-cover-placeholder`,
            layerId: card.layerId,
            type: "rect",
            x: 12,
            y: 12,
            width: 148,
            height: 222,
            fill: 0xe7e8eb,
            stroke: 0xc9ccd2,
            strokeWidth: 1,
            cornerRadius: 5,
          });
      const elements: CanvasObject[] = [cover];
      if (!data.coverMediaId)
        elements.push(
          text(card, "placeholder", "BOOK", 46, 108, 80, 13, 0x7c828d, 24),
        );
      elements.push(
        text(card, "title", data.title, 12, 242, 148, 15, 0x172033, 38, 18, 2),
      );
      return new IllustrationCard({ ...card, kind: "canvas", elements });
    },
    hoverLabel(card, context) {
      const data = normalizeBook(card.pluginData);
      const author = context.resolvePersonName(
        data.authorPersonId,
        data.authorName,
      );
      return `${data.title || "Book"} by ${author || "Unknown author"}`;
    },
    Editor: {
      Component: BookEditor,
      createDraft(data) {
        return { ...normalizeBook(data), coverInput: null, removeCover: false };
      },
      schema: bookSchema,
      async commit(draft, services) {
        let authorPersonId = draft.authorPersonId;
        let authorName = draft.authorName.trim();
        if (!authorPersonId) {
          const person = await services.savePerson({
            id: crypto.randomUUID(),
            name: authorName,
            role: "",
            organization: "",
            notes: "",
          });
          authorPersonId = person.id;
          authorName = person.name;
        } else {
          authorName = services.resolvePersonName(authorPersonId, authorName);
        }
        let coverMediaId = draft.removeCover ? null : draft.coverMediaId;
        let coverWidth = draft.removeCover ? null : draft.coverWidth;
        let coverHeight = draft.removeCover ? null : draft.coverHeight;
        if (draft.coverInput) {
          const asset = await services.importImage(draft.coverInput);
          coverMediaId = asset.id;
          coverWidth = asset.width ?? draft.coverInput.width;
          coverHeight = asset.height ?? draft.coverInput.height;
        }
        return normalizeBook({
          ...draft,
          title: draft.title.trim(),
          authorPersonId,
          authorName,
          coverMediaId,
          coverWidth,
          coverHeight,
        });
      },
    },
  },
  lifecycle: {},
});

type PersonData = Record<string, unknown> & {
  personId: string | null;
  name: string;
  role: string;
  organization: string;
  notes: string;
};

const normalizePerson = (value: unknown): PersonData => {
  const data =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  return {
    personId: typeof data.personId === "string" ? data.personId : null,
    name: typeof data.name === "string" ? data.name : "",
    role: typeof data.role === "string" ? data.role : "",
    organization:
      typeof data.organization === "string" ? data.organization : "",
    notes: typeof data.notes === "string" ? data.notes : "",
  };
};

const personSchema = z
  .object({ name: z.string().trim().min(1, "Enter a name.") })
  .passthrough() as unknown as z.ZodType<PersonData>;

function PersonEditor({
  draft,
  onChange,
  fieldErrors,
}: CardPluginEditorProps<PersonData>) {
  const patch = (value: Partial<PersonData>) =>
    onChange({ ...draft, ...value });
  return (
    <div className="card-editor-fields">
      <label>
        Name
        <Input
          autoFocus
          value={draft.name}
          placeholder="Name"
          aria-invalid={Boolean(fieldErrors.name)}
          onChange={(event) => patch({ name: event.currentTarget.value })}
        />
        <FieldError messages={fieldErrors.name} />
      </label>
      <label>
        Role
        <Input
          value={draft.role}
          placeholder="Role"
          onChange={(event) => patch({ role: event.currentTarget.value })}
        />
      </label>
      <label>
        Organization
        <Input
          value={draft.organization}
          placeholder="Organization"
          onChange={(event) =>
            patch({ organization: event.currentTarget.value })
          }
        />
      </label>
      <label>
        Notes
        <Textarea
          value={draft.notes}
          placeholder="Notes"
          onChange={(event) => patch({ notes: event.currentTarget.value })}
        />
      </label>
    </div>
  );
}

export const personCard = defineCardPlugin<PersonData>({
  manifest: {
    id: "notes.person-card",
    name: "Person",
    description: "A structured person profile.",
    version: "2.0.0",
    author: "Productivity OS",
    marketplace: false,
    card: {
      type: "person",
      schemaVersion: 2,
      defaultDimensions: { width: 340, height: 220 },
    },
  },
  propertiesPanel: "hidden",
  create(context) {
    return createPluginCard(this.manifest, context, normalizePerson(null));
  },
  hydrate: normalizePerson,
  serialize: normalizePerson,
  migrate: normalizePerson,
  slots: {
    ToolbarIcon: UserRound,
    canvasRender(card, context) {
      const data = normalizePerson(card.pluginData);
      const name = context.resolvePersonName(data.personId, data.name);
      return new IllustrationCard({
        ...card,
        kind: "canvas",
        elements: [
          new RectangleObject({
            id: `${card.id}-avatar`,
            layerId: card.layerId,
            type: "rect",
            x: 24,
            y: 28,
            width: 72,
            height: 72,
            fill: 0xf0d9cb,
            stroke: 0xd5b8a6,
            strokeWidth: 1,
            cornerRadius: 24,
          }),
          text(card, "title", name, 116, 30, 196, 24),
          text(card, "role", data.role || "Role", 116, 72, 196, 16, 0x64748b),
          text(
            card,
            "organization",
            data.organization,
            24,
            122,
            288,
            16,
            0x475569,
          ),
          text(card, "notes", data.notes, 24, 158, 288, 14, 0x64748b),
        ],
      });
    },
    Editor: {
      Component: PersonEditor,
      createDraft: normalizePerson,
      schema: personSchema,
      async commit(draft, services) {
        const saved = await services.savePerson({
          id: draft.personId ?? crypto.randomUUID(),
          name: draft.name,
          role: draft.role,
          organization: draft.organization,
          notes: draft.notes,
        });
        return normalizePerson({
          ...draft,
          personId: saved.id,
          name: saved.name,
          role: saved.role,
          organization: saved.organization,
          notes: saved.notes,
        });
      },
    },
  },
  lifecycle: {},
});

type NotebookData = Record<string, unknown> & {
  targetNotebookId: string;
  targetNotebookTitle: string;
  icon: string;
};
const normalizeNotebook = (value: unknown): NotebookData => {
  const data =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  return {
    targetNotebookId:
      typeof data.targetNotebookId === "string" ? data.targetNotebookId : "",
    targetNotebookTitle:
      typeof data.targetNotebookTitle === "string"
        ? data.targetNotebookTitle
        : "",
    icon: typeof data.icon === "string" ? data.icon : "📓",
  };
};
const notebookSchema = z
  .object({ targetNotebookId: z.string().min(1, "Choose a notebook.") })
  .passthrough() as unknown as z.ZodType<NotebookData>;

function NotebookEditor({
  draft,
  onChange,
  services,
  fieldErrors,
}: CardPluginEditorProps<NotebookData>) {
  const [notebooks, setNotebooks] = useState<
    Awaited<ReturnType<typeof services.listNotebooks>>
  >([]);
  useEffect(() => {
    void services.listNotebooks().then(setNotebooks);
  }, [services]);
  return (
    <div
      className="notebook-card-picker"
      role="listbox"
      aria-invalid={Boolean(fieldErrors.targetNotebookId)}
    >
      {notebooks.map((notebook) => (
        <Button
          key={notebook.id}
          type="button"
          variant={
            draft.targetNotebookId === notebook.id ? "secondary" : "ghost"
          }
          role="option"
          aria-selected={draft.targetNotebookId === notebook.id}
          onClick={() =>
            onChange({
              ...draft,
              targetNotebookId: notebook.id,
              targetNotebookTitle: notebook.title,
              icon: notebook.icon,
            })
          }
        >
          <span>{notebook.icon}</span>
          {notebook.title}
        </Button>
      ))}
      {notebooks.length === 0 && <p>No notebooks available.</p>}
      <FieldError messages={fieldErrors.targetNotebookId} />
    </div>
  );
}

export const notebookCard = defineCardPlugin<NotebookData>({
  manifest: {
    id: "notes.notebook-card",
    name: "Notebook",
    description: "A link to another notebook.",
    version: "2.0.0",
    author: "Productivity OS",
    marketplace: false,
    card: {
      type: "notebook",
      schemaVersion: 2,
      defaultDimensions: { width: 320, height: 180 },
    },
  },
  propertiesPanel: "editor",
  create(context) {
    return createPluginCard(this.manifest, context, normalizeNotebook(null));
  },
  hydrate: normalizeNotebook,
  serialize: normalizeNotebook,
  migrate: normalizeNotebook,
  slots: {
    ToolbarIcon: NotebookTabs,
    canvasRender(card) {
      const data = normalizeNotebook(card.pluginData);
      return new IllustrationCard({
        ...card,
        kind: "canvas",
        elements: [
          text(card, "icon", data.icon, 26, 26, 64, 32),
          text(card, "eyebrow", "NOTEBOOK", 26, 76, 250, 14, 0x64748b),
          text(
            card,
            "title",
            data.targetNotebookTitle || "Missing notebook",
            26,
            106,
            268,
            24,
          ),
        ],
      });
    },
    Editor: {
      Component: NotebookEditor,
      createDraft: normalizeNotebook,
      schema: notebookSchema,
      commit: normalizeNotebook,
    },
  },
  lifecycle: {},
});

export const permanentCards = [bookCard, personCard, notebookCard] as const;
