import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";
import {
  applyNotebookRootArrowStyle,
  allowsNotebookInsertion,
  migrateNotebookRootArrows,
  migrateLegacyNotebookTextStyles,
  toolsForNotebookDepth,
} from "../src/canvas/notebook-policy.ts";

test("legacy default text chrome migrates recursively without changing intentional styles", () => {
  const legacy = {
    id: "legacy",
    type: "text",
    backgroundColor: 0xffffff,
    borderColor: 0x3b82f6,
    borderWidth: 2,
  };
  const intentional = {
    id: "intentional",
    type: "text",
    backgroundColor: 0xffffff,
    borderColor: 0xef4444,
    borderWidth: 2,
  };
  const objects = [
    { id: "card", type: "card", elements: [legacy, intentional] },
  ] as never;
  assert.equal(migrateLegacyNotebookTextStyles(objects), true);
  assert.equal(legacy.backgroundColor, undefined);
  assert.equal(legacy.borderColor, undefined);
  assert.equal(legacy.borderWidth, 0);
  assert.equal(intentional.borderColor, 0xef4444);
  assert.equal(migrateLegacyNotebookTextStyles(objects), false);
});

test("Markdown tools use Notes artwork, empty content, transparent text, and live viewport layout", () => {
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const blankEditor = readFileSync(
    new URL("../src/components/blank-card-editor-dialog.tsx", import.meta.url),
    "utf8",
  );
  const icon = readFileSync(
    new URL("../src/components/markdown-tool-icon.tsx", import.meta.url),
    "utf8",
  );
  const creation = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/runtime/creation-session.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const controller = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/runtime/canvas.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const editor = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/interaction/markdown-live-editor.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const vite = readFileSync(
    new URL("../vite.config.ts", import.meta.url),
    "utf8",
  );
  const latex = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/latex/latex.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const typography = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/markdown/markdown-typography.ts",
      import.meta.url,
    ),
    "utf8",
  );
  assert.equal(
    existsSync(
      new URL(
        "../src/assets/icons/svg/markdown-svgrepo-com.svg",
        import.meta.url,
      ),
    ),
    true,
  );
  assert.match(icon, /maskImage/);
  const iconSvg = readFileSync(
    new URL(
      "../src/assets/icons/svg/markdown-svgrepo-com.svg",
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(iconSvg, /viewBox="0 0 32 32"/);
  assert.match(iconSvg, /fill-rule="evenodd"/);
  assert.match(detail, /markdown: ""/);
  assert.match(blankEditor, /defaultTextFormat: "markdown"/);
  assert.match(blankEditor, /preferredTools=\{\{ text: "markdown" \}\}/);
  assert.match(creation, /backgroundColor: undefined/);
  assert.match(creation, /borderWidth: 0/);
  assert.doesNotMatch(creation, /Start writing/);
  assert.match(controller, /updateTextEditingLayout/);
  assert.match(editor, /dataset\.placeholder = "Write Markdown"/);
  assert.match(editor, /border: "2px solid #3b82f6"/);
  assert.match(editor, /borderRadius/);
  assert.match(typography, /lineHeight: 19/);
  assert.match(typography, /paragraphGap: "\.15em"/);
  assert.match(vite, /notes-disable-unused-mathjax-speech-worker/);
  assert.match(latex, /enableSpeech: false/);
  assert.match(latex, /mathJaxPromise = null/);
});

test("root and card panes expose mutually exclusive creation tools", () => {
  const root = toolsForNotebookDepth(0);
  const inside = toolsForNotebookDepth(1);
  assert.ok(
    root.includes("card") && root.includes("arrow") && root.includes("line"),
  );
  assert.ok(
    !root.includes("text") && !root.includes("image") && !root.includes("rect"),
  );
  assert.ok(
    inside.includes("text") &&
      inside.includes("image") &&
      inside.includes("rect"),
  );
  assert.ok(
    !inside.includes("card") &&
      !inside.includes("markdown-card") &&
      !inside.includes("add"),
  );
});

test("legacy root arrows migrate to thick purple without touching custom or nested content", () => {
  const nested = { type: "arrow", stroke: 0x334155, strokeWidth: 2.5 };
  const snapshot = {
    schemaVersion: 3,
    objects: [
      {
        objectType: "arrow",
        payload: {
          type: "arrow",
          renderMode: "between",
          stroke: 0x334155,
          strokeWidth: 2,
        },
      },
      {
        objectType: "arrow",
        payload: { type: "arrow", stroke: 0xef4444, strokeWidth: 2.5 },
      },
      { objectType: "card", payload: { type: "card", elements: [nested] } },
    ],
  };
  assert.equal(migrateNotebookRootArrows(snapshot), true);
  assert.equal(snapshot.schemaVersion, 5);
  assert.deepEqual(snapshot.objects[0]?.payload, {
    type: "arrow",
    renderMode: "between",
    stroke: 0x7c3aed,
    strokeWidth: 4,
  });
  assert.deepEqual(snapshot.objects[1]?.payload, {
    type: "arrow",
    stroke: 0xef4444,
    strokeWidth: 2.5,
  });
  assert.deepEqual(nested, {
    type: "arrow",
    stroke: 0x334155,
    strokeWidth: 2.5,
  });
  assert.equal(migrateNotebookRootArrows(snapshot), false);
});

test("new root card connectors are normalized before their first render", () => {
  const arrow = {
    type: "arrow",
    renderMode: "between",
    stroke: 0x334155,
    strokeWidth: 2,
  };
  assert.equal(applyNotebookRootArrowStyle(arrow, { stackLevel: 0 }), true);
  assert.deepEqual(arrow, {
    type: "arrow",
    renderMode: "between",
    stroke: 0x7c3aed,
    strokeWidth: 4,
  });

  const nested = {
    type: "arrow",
    renderMode: "between",
    stroke: 0x334155,
    strokeWidth: 2,
  };
  assert.equal(applyNotebookRootArrowStyle(nested, { stackLevel: 1 }), false);
  assert.equal(nested.stroke, 0x334155);

  const custom = {
    type: "arrow",
    renderMode: "between",
    stroke: 0xef4444,
    strokeWidth: 8,
  };
  assert.equal(applyNotebookRootArrowStyle(custom, { stackLevel: 0 }), false);
  assert.equal(custom.stroke, 0xef4444);
  assert.equal(custom.strokeWidth, 8);
});

test("the shared insertion policy blocks UI and non-UI bypasses", () => {
  for (const type of ["text", "image", "video", "rect", "path"] as const) {
    assert.equal(
      allowsNotebookInsertion({ type } as never, { stackLevel: 0 }),
      false,
    );
  }
  assert.equal(
    allowsNotebookInsertion({ type: "card" } as never, { stackLevel: 0 }),
    true,
  );
  assert.equal(
    allowsNotebookInsertion({ type: "arrow" } as never, { stackLevel: 0 }),
    true,
  );
  assert.equal(
    allowsNotebookInsertion({ type: "card" } as never, { stackLevel: 1 }),
    false,
  );
  assert.equal(
    allowsNotebookInsertion({ type: "text" } as never, { stackLevel: 1 }),
    true,
  );
});

test("Notes owns its Tauri identity, detail windows, and build-time plugin marketplace", () => {
  const config = readFileSync(
    new URL("../src-tauri/tauri.conf.json", import.meta.url),
    "utf8",
  );
  const backend = readFileSync(
    new URL("../src-tauri/src/lib.rs", import.meta.url),
    "utf8",
  );
  const question = JSON.parse(
    readFileSync(
      new URL("../../../plugins/question-card/manifest.json", import.meta.url),
      "utf8",
    ),
  );
  assert.match(config, /com\.productivity-os\.notes/);
  assert.doesNotMatch(config, /canvas\/src-tauri\/icons/);
  assert.match(config, /icons\/icon\.icns/);
  assert.match(backend, /get_webview_window\(&label\)/);
  assert.match(backend, /WebviewWindowBuilder/);
  assert.equal(question.defaultInstalled, true);
  assert.equal(question.cardType, "question");
});

test("Notes Home consumes the shared dark library and canonical application header", () => {
  const home = readFileSync(
    new URL("../src/pages/Home.tsx", import.meta.url),
    "utf8",
  );
  const app = readFileSync(new URL("../src/App.tsx", import.meta.url), "utf8");
  const main = readFileSync(
    new URL("../src/main.tsx", import.meta.url),
    "utf8",
  );
  const workflowsIndex = readFileSync(
    new URL("../../Workflows/src/pages/Index.tsx", import.meta.url),
    "utf8",
  );
  const sharedSidebar = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/workspace-sidebar.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const sharedStyles = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/styles/styles.css",
      import.meta.url,
    ),
    "utf8",
  );
  const sharedHeader = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/app-header.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const sharedProvider = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/shared-ui-provider.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const workflowsApp = readFileSync(
    new URL("../../Workflows/src/App.tsx", import.meta.url),
    "utf8",
  );
  const workflowsMain = readFileSync(
    new URL("../../Workflows/src/main.tsx", import.meta.url),
    "utf8",
  );

  assert.match(home, /WorkspaceLibraryShell/);
  assert.match(home, /WorkspacePreviewCard/);
  assert.match(home, /WorkspaceAppHeader/);
  assert.match(home, /breadcrumbs=/);
  assert.match(home, /tabs=\{\[\]\}/);
  assert.doesNotMatch(home, /addTab=/);
  assert.match(main, /defaultTheme="dark"/);
  assert.match(main, /<SharedUiProvider/);
  assert.match(
    main,
    /applicationBackgroundMenu=\{isNotebookWindow \? "none" : "reload"\}/,
  );
  assert.match(main, /@productivity-os\/shared-ui\/globals\.css/);
  assert.match(workflowsMain, /<SharedUiProvider>/);
  assert.match(workflowsApp, /<WorkspaceAppHeader/);
  assert.match(workflowsIndex, /WorkspaceLibraryShell/);
  assert.match(workflowsIndex, /WorkspaceLibraryToolbar/);
  assert.match(sharedSidebar, /WorkspaceSidebarFooterItem/);
  assert.match(sharedStyles, /background: #292929 !important/);
  assert.match(sharedStyles, /font-size: 10px !important/);
  assert.match(sharedHeader, /after:h-\[3px\]/);
  assert.match(sharedHeader, /function WorkspaceAppHeader/);
  assert.match(sharedProvider, /<TooltipProvider/);
  assert.match(sharedProvider, /<ApplicationContextMenu backgroundAction=/);
  assert.doesNotMatch(sharedStyles, /\.ps-app-header/);
});

test("shared menus, Media attachments, and milestone loading are used across apps", () => {
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const media = readFileSync(
    new URL("../src/pages/Media.tsx", import.meta.url),
    "utf8",
  );
  const sidebar = readFileSync(
    new URL("../src/components/notes-home-sidebar.tsx", import.meta.url),
    "utf8",
  );
  const sharedMedia = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/workspace-media-library.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const canvasMenu = readFileSync(
    new URL(
      "../../../packages/canvas/src/react/canvas-surface-context-menu.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const core = readFileSync(
    new URL("../../../crates/core/src/lib.rs", import.meta.url),
    "utf8",
  );
  const blankEditor = readFileSync(
    new URL("../src/components/blank-card-editor-dialog.tsx", import.meta.url),
    "utf8",
  );
  const applicationMenu = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/application-context-menu.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const nativeClipboard = readFileSync(
    new URL("../src/api/tauri-canvas-clipboard.ts", import.meta.url),
    "utf8",
  );
  const capability = readFileSync(
    new URL("../src-tauri/capabilities/default.json", import.meta.url),
    "utf8",
  );

  assert.match(sidebar, /id: "media"/);
  assert.doesNotMatch(sidebar, /label: "Resources"/);
  assert.match(media, /WorkspaceMediaLibrary/);
  assert.match(sharedMedia, /Attachment/);
  assert.match(sharedMedia, /Reveal in folder/);
  assert.match(sharedMedia, /missing-media placeholder/);
  assert.match(detail, /<Progress value=\{loadState\.progress\}/);
  assert.match(detail, /onReady=\{handleCanvasReady\}/);
  assert.match(detail, /CanvasSurfaceContextMenu/);
  assert.match(canvasMenu, /platformShortcut/);
  assert.match(canvasMenu, /target\.actions/);
  assert.match(
    blankEditor,
    /<CanvasSurfaceContextMenu canvasRef=\{canvasRef\}>/,
  );
  assert.doesNotMatch(applicationMenu, /label: "Back"|label: "Forward"/);
  assert.match(applicationMenu, /backgroundAction === "reload"/);
  assert.match(nativeClipboard, /readImage/);
  assert.match(nativeClipboard, /writeImage/);
  assert.match(capability, /clipboard-manager:allow-write-image/);
  assert.match(detail, /onExternalImagePaste: createPastedImageCard/);
  assert.match(detail, /importNotebookImage/);
  assert.match(detail, /320 \/ Math\.max/);
  assert.match(core, /DATA_SERVICE_PROTOCOL_VERSION: u32 = 17/);
  assert.match(core, /GetMediaEntry/);
  assert.match(core, /canvas_type: Option<CanvasType>/);
  assert.equal(
    existsSync(
      new URL("../../Workflows/src/pages/Resources.tsx", import.meta.url),
    ),
    false,
  );
});

test("book covers use a focused paste target with hover actions and progress", () => {
  const coverInput = readFileSync(
    new URL("../src/components/book-cover-input.tsx", import.meta.url),
    "utf8",
  );
  const styles = readFileSync(
    new URL("../src/App.css", import.meta.url),
    "utf8",
  );

  assert.match(coverInput, /aria-label="Book cover image input"/);
  assert.match(coverInput, /onPaste=/);
  assert.match(coverInput, /data-selected=/);
  assert.match(coverInput, /<Progress value=\{progress\}/);
  assert.match(coverInput, /<ImagePlus \/>/);
  assert.match(coverInput, /<X \/>/);
  assert.match(coverInput, />\s*Upload\s*</);
  assert.match(coverInput, />\s*Clear\s*</);
  assert.doesNotMatch(coverInput, />\s*(Select|Replace|Paste|Remove)\s*</);
  assert.doesNotMatch(coverInput, /book-cover-actions/);
  assert.match(styles, /\.book-cover-preview\[data-selected\]/);
  assert.match(styles, /\.book-cover-progress/);
});

test("notebook detail windows expose native dragging and stable canvas adapters", () => {
  const capability = JSON.parse(
    readFileSync(
      new URL("../src-tauri/capabilities/default.json", import.meta.url),
      "utf8",
    ),
  ) as { permissions: string[] };
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const endlessCanvas = readFileSync(
    new URL(
      "../../../packages/canvas/src/react/EndlessCanvas.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const app = readFileSync(new URL("../src/App.tsx", import.meta.url), "utf8");
  const errorBoundary = readFileSync(
    new URL("../src/components/notebook-error-boundary.tsx", import.meta.url),
    "utf8",
  );
  const sharedHeader = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/app-header.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const backend = readFileSync(
    new URL("../src-tauri/src/lib.rs", import.meta.url),
    "utf8",
  );

  for (const permission of [
    "core:window:allow-close",
    "core:window:allow-destroy",
    "core:window:allow-minimize",
    "core:window:allow-toggle-maximize",
    "core:window:allow-start-dragging",
  ]) {
    assert.ok(
      capability.permissions.includes(permission),
      `missing ${permission}`,
    );
  }

  assert.match(detail, /<WorkspaceDocumentHeader/);
  assert.match(sharedHeader, /function WorkspaceDocumentHeader/);
  assert.match(sharedHeader, /data-tauri-drag-region/);
  assert.match(sharedHeader, /text-\[10px\]/);
  assert.match(sharedHeader, /text-\[9px\]/);
  assert.match(sharedHeader, /border-b border-border/);
  assert.match(sharedHeader, /max-w-\[50%\]/);
  assert.match(sharedHeader, /h-full min-w-8 flex-1/);
  assert.match(detail, /const paneDepthRef = useRef/);
  assert.match(detail, /const handlePaneChange = useCallback/);
  assert.match(detail, /const handleViewportChange = useCallback/);
  assert.doesNotMatch(detail, /aria-label="Home"/);
  assert.match(detail, /CanvasToolbar/);
  assert.doesNotMatch(detail, /NotesToolbar/);
  assert.doesNotMatch(
    detail,
    /aria-label="(Notebook panel|Favorite|Export|Minimize|Maximize|Close)"/,
  );
  assert.match(backend, /toggle_notebook_favorite/);
  assert.match(backend, /export_notebook/);
  assert.match(backend, /toggle_notebook_panel/);
  assert.match(backend, /focused_notebook_window/);
  assert.match(endlessCanvas, /const callbacksRef = useRef/);
  assert.match(endlessCanvas, /latest\.onViewportChange/);
  assert.match(endlessCanvas, /latest\.onChange/);
  assert.match(app, /<NotebookErrorBoundary>/);
  assert.match(errorBoundary, /Couldn’t open this notebook/);
  assert.match(errorBoundary, /window\.location\.reload/);
});

test("notebook roots use the vector minimap and canvases retain shared renderer resources", () => {
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const minimap = readFileSync(
    new URL(
      "../../../packages/canvas/src/react/canvas-minimap.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const minimapStyles = readFileSync(
    new URL(
      "../../../packages/canvas/src/react/canvas-minimap.css",
      import.meta.url,
    ),
    "utf8",
  );
  const notesStyles = readFileSync(
    new URL("../src/App.css", import.meta.url),
    "utf8",
  );
  const engine = readFileSync(
    new URL(
      "../../../packages/canvas/src/core/engine/engine.ts",
      import.meta.url,
    ),
    "utf8",
  );

  assert.match(detail, /pane\.stackLevel === 0/);
  assert.match(detail, /pane\.stackLevel === 0\s*&&\s*!panelOpen/);
  assert.match(detail, /<CanvasMinimap canvasRef=\{canvasRef\}/);
  assert.match(minimap, /subscribeOverview/);
  assert.match(minimap, /fitAllVisible/);
  assert.match(minimap, /setViewportCenter/);
  assert.match(minimap, /canvas-minimap-card/);
  assert.match(minimap, /<polyline/);
  assert.match(minimap, /canvas-minimap-actions/);
  assert.match(minimap, /CARD_RADIUS_PX = 3/);
  assert.match(minimap, /CARD_MIN_SIZE_PX = 6/);
  assert.match(minimap, /ResizeObserver/);
  assert.doesNotMatch(minimap, /captureSnapshot|<img|<canvas/);
  assert.match(minimapStyles, /--canvas-minimap-background: var\(--sidebar\)/);
  assert.match(
    minimapStyles,
    /--canvas-minimap-viewport: var\(\s*--workspace-accent,\s*var\(--shared-ui-accent, #3b82f6\)/,
  );
  assert.doesNotMatch(minimapStyles, /--canvas-minimap-viewport:\s*#7c3aed/);
  assert.match(
    notesStyles,
    /\.canvas-minimap\.notebook-minimap[\s\S]*right: auto;[\s\S]*left: 14px;/,
  );
  assert.match(engine, /releaseGlobalResources: false/);
  assert.doesNotMatch(engine, /markdownTextRenderer\.destroy/);
  assert.doesNotMatch(engine, /videoPlaybackRegistry\.destroy/);
});

test("notebook property presets use shared theme-aware buttons", () => {
  const properties = readFileSync(
    new URL("../src/components/discrete-properties.tsx", import.meta.url),
    "utf8",
  );
  const styles = readFileSync(
    new URL("../src/App.css", import.meta.url),
    "utf8",
  );
  assert.match(properties, /shared-ui\/components\/ui\/button/);
  assert.match(properties, /className="property-preset-button"/);
  assert.match(properties, /variant="outline"/);
  assert.match(styles, /background: var\(--background\)/);
  assert.match(styles, /var\(--workspace-accent\)/);
});

test("card plugins own toolbar icons, overlay editors, properties policy, and media", () => {
  const api = readFileSync(
    new URL("../src/plugins/plugin-api.tsx", import.meta.url),
    "utf8",
  );
  const cards = readFileSync(
    new URL("../src/plugins/builtin-cards.tsx", import.meta.url),
    "utf8",
  );
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const question = readFileSync(
    new URL("../../../plugins/question-card/index.tsx", import.meta.url),
    "utf8",
  );
  const toolbar = readFileSync(
    new URL(
      "../../../packages/canvas/src/react/canvas-toolbar.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  const backend = readFileSync(
    new URL("../src-tauri/src/lib.rs", import.meta.url),
    "utf8",
  );

  assert.match(api, /ToolbarIcon:/);
  assert.match(api, /propertiesPanel: "hidden" \| "editor"/);
  assert.match(api, /schema: ZodType/);
  assert.match(cards, /ToolbarIcon: BookOpen/);
  assert.match(cards, /ToolbarIcon: UserRound/);
  assert.match(cards, /ToolbarIcon: NotebookTabs/);
  assert.match(question, /ToolbarIcon: CircleHelp/);
  assert.match(question, /schemaVersion: 2/);
  assert.match(
    question,
    /defaultDimensions: \{ width: CARD_WIDTH, height: CLOZE_MIN_HEIGHT \}/,
  );
  assert.match(question, /frontHeight/);
  assert.match(question, /backHeight/);
  assert.match(question, /capture: false/);
  assert.doesNotMatch(question, /CardPluginEditorProps/);
  assert.doesNotMatch(question, /^\s+Editor:/m);
  assert.match(cards, /width: 172, height: 294/);
  assert.match(cards, /148, 15, 0x172033, 38, 18, 2/);
  assert.match(cards, /coverMediaId/);
  assert.match(cards, /Unknown author/);
  assert.match(detail, /<BlankCardEditorDialog/);
  assert.match(detail, /<CardEditorDialog/);
  assert.match(detail, /nextCustomMenuItem/);
  assert.match(detail, /label: "Question"/);
  assert.match(detail, /event\.key\.toLowerCase\(\) === "q"/);
  assert.match(detail, /PluginInlineEditorOverlay/);
  assert.match(toolbar, /selectedItem\?\.icon/);
  assert.match(backend, /import_notebook_media/);
  assert.match(backend, /register_asynchronous_uri_scheme_protocol\("media"/);
  assert.match(backend, /Cross-Origin-Resource-Policy/);
});

test("cards draw before validated editors and authors use global person records", () => {
  const detail = readFileSync(
    new URL("../src/pages/NotebookDetail.tsx", import.meta.url),
    "utf8",
  );
  const dialog = readFileSync(
    new URL("../src/components/card-editor-dialog.tsx", import.meta.url),
    "utf8",
  );
  const blankDialog = readFileSync(
    new URL("../src/components/blank-card-editor-dialog.tsx", import.meta.url),
    "utf8",
  );
  const personInput = readFileSync(
    new URL("../src/components/person-input.tsx", import.meta.url),
    "utf8",
  );
  const cards = readFileSync(
    new URL("../src/plugins/builtin-cards.tsx", import.meta.url),
    "utf8",
  );
  const core = readFileSync(
    new URL("../../../crates/core/src/lib.rs", import.meta.url),
    "utf8",
  );
  const migration = readFileSync(
    new URL(
      "../../../crates/database/migrations/202609060001_create_persons.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const styles = readFileSync(
    new URL("../src/App.css", import.meta.url),
    "utf8",
  );

  assert.match(detail, /onAddToolDraw: placeDrawnCard/);
  assert.match(detail, /placement\.dragged \? placement\.bounds : undefined/);
  assert.match(detail, /expandCardToContent/);
  assert.match(detail, /stroke: 0x7c3aed, strokeWidth: 4/);
  assert.doesNotMatch(detail, /chooseNotebook|setChooseNotebook/);
  assert.match(cards, /Component: NotebookEditor/);
  assert.match(cards, /schema: bookSchema/);
  assert.match(cards, /schema: personSchema/);
  assert.match(cards, /schema: notebookSchema/);
  assert.doesNotMatch(cards, /"Untitled book"|"New person"/);
  assert.match(dialog, /editor\.schema\.safeParse/);
  assert.match(dialog, /event\.metaKey \|\| event\.ctrlKey/);
  assert.match(blankDialog, /event\.metaKey && !event\.ctrlKey/);
  assert.match(personInput, /Combobox<PersonRecord>/);
  assert.match(personInput, /services\.savePerson/);
  assert.match(core, /pub struct PersonRecord/);
  assert.match(core, /ListPersons/);
  assert.match(core, /SavePerson/);
  assert.match(migration, /CREATE TABLE persons/);
  assert.match(migration, /notes\.book-card/);
  assert.match(styles, /filter: blur\(2px\) brightness\(0\.62\)/);
});

test("notebook card renaming survives context-menu focus restoration", () => {
  const home = readFileSync(
    new URL("../src/pages/Home.tsx", import.meta.url),
    "utf8",
  );
  const library = readFileSync(
    new URL(
      "../../../packages/shared-ui/src/components/workspace-library.tsx",
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(library, /renameFocusReadyRef/);
  assert.match(
    library,
    /window\.setTimeout\(\(\) => \{[\s\S]*renameFocusReadyRef\.current = true/,
  );
  assert.match(
    library,
    /nextTarget instanceof Node && card\?\.contains\(nextTarget\)/,
  );
  assert.match(
    library,
    /window\.requestAnimationFrame\(\(\) => inputRef\.current\?\.select\(\)\)/,
  );
  assert.match(home, /<BookOpen aria-hidden="true" \/>[\s\S]*Open/);
  assert.match(home, /<BrainCircuit aria-hidden="true" \/>[\s\S]*Review/);
  assert.match(home, /<PencilLine aria-hidden="true" \/>[\s\S]*Rename/);
  assert.match(home, /<Trash2 aria-hidden="true" \/>[\s\S]*Delete/);
  assert.doesNotMatch(home, />\s*Favorite\s*</);
});
