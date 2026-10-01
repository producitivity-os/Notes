import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const source = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8")

test("tier editor autosaves and forced dismissal flushes instead of cancelling", () => {
  const editor = source("../src/components/blank-card-editor-dialog.tsx")
  const styles = source("../src/App.css")
  assert.match(editor, /AUTOSAVE_DELAY = 1_500/)
  assert.match(editor, /window\.setTimeout\(\(\) => void flush\(\), AUTOSAVE_DELAY\)/)
  assert.match(editor, /onEscapeKeyDown/)
  assert.match(editor, /onPointerDownOutside/)
  assert.match(editor, /window\.addEventListener\("blur", blur\)/)
  assert.match(editor, /if \(!\(await flush\(\)\)\)/)
  assert.match(editor, /await onClose\(\)/)
  assert.doesNotMatch(editor, /DialogFooter|>\s*Save\s*<|>\s*Cancel\s*</)
  assert.doesNotMatch(editor, /Saved|Saving…|card-tier-dimensions/)
  assert.match(editor, /initialStatesRef\.current!\.get\(tier\.id\)/)
  assert.match(styles, /\.card-tier-appendage \{[\s\S]*?border-top:/)
  assert.match(editor, /className="card-tier-appendage"/)
  assert.match(editor, /onClick=\{addTier\}/)
  assert.match(
    styles,
    /\.card-tier-section \.blank-card-editor-canvas \{\s*position: absolute;\s*inset: 0;/,
  )
})

test("card bounds stay fixed while tier content and previews are saved", () => {
  const detail = source("../src/pages/NotebookDetail.tsx")
  const editor = source("../src/components/blank-card-editor-dialog.tsx")
  const canvas = source("../../../../packages/canvas/src/core/runtime/canvas.ts")
  assert.match(detail, /objectCapabilities: \{ card: \{ resizable: false/)
  assert.match(detail, /preserveCardDimensions: true/)
  assert.match(detail, /const width = 220;?\s*const height = 140;?/)
  assert.match(detail, /width: stored\?\.width \?\? existing\.width/)
  assert.doesNotMatch(detail, /expandCardToContent\(fixed\)/)
  assert.doesNotMatch(editor, /aria-label=\{`\$\{tier\.name\} width`\}/)
  assert.doesNotMatch(editor, /aria-label=\{`\$\{tier\.name\} height`\}/)
  assert.match(canvas, /!candidate\.capabilities\.resizable\) return false/)
})

test("native card editor windows use acknowledged saves and silent status UI", () => {
  const app = source("../src/App.tsx")
  const child = source("../src/components/card-editor-window.tsx")
  const detail = source("../src/pages/NotebookDetail.tsx")
  const rust = source("../src-tauri/src/lib.rs")
  const styles = source("../src/App.css")
  assert.match(app, /cardEditorSession/)
  assert.match(child, /notes:card-editor-save-result/)
  assert.match(child, /getCurrentWindow\(\)\s*\.listen/)
  assert.match(detail, /notes:card-editor-save-request/)
  assert.match(detail, /getCurrentWindow\(\)\.listen<CardEditorSaveRequest>/)
  assert.match(rust, /WebviewWindowBuilder::new/)
  assert.match(rust, /\.parent\(&parent\)/)
  assert.doesNotMatch(rust, /parent\s*\.set_enabled\(false\)/)
  assert.match(rust, /notes:card-editor-lifecycle/)
  assert.match(rust, /restore_card_editor_parent/)
  assert.match(detail, /getCurrentWindow\(\)\.listen<CardEditorLifecycle>/)
  assert.match(detail, /inert=\{cardEditorWindowOpen \? true : undefined\}/)
  assert.match(styles, /\.detail-card-editor-shield/)
  assert.match(styles, /\.tiered-card-editor-window \{/)
  assert.match(styles, /\.detail-loading-overlay \{[\s\S]*inset: 32px 0 0;/)
  assert.doesNotMatch(detail, /Saved|Saving…/)
})

test("Notes Explorer uses the shared sidebar and native preferences", () => {
  const home = source("../src/pages/Home.tsx")
  const sidebar = source("../src/components/notes-home-sidebar.tsx")
  const app = source("../src/App.tsx")
  const rust = source("../src-tauri/src/lib.rs")
  const preferences = source("../src-tauri/src/preferences.rs")
  const nativePreferences = source(
    "../../../../crates/desktop-menu/src/preferences.rs",
  )
  const config = source("../src-tauri/tauri.conf.json")
  const shared = source(
    "../../../../packages/shared-ui/src/components/application-sidebar.tsx",
  )
  assert.match(home, /ApplicationSidebarLayout/)
  assert.doesNotMatch(home, /WorkspaceAppHeader|Settings/) 
  assert.doesNotMatch(sidebar, /name="Notes"|notesLogo/)
  assert.match(shared, /aria-label="Collapse sidebar"/)
  assert.match(shared, /aria-label="Expand sidebar"/)
  assert.doesNotMatch(shared, /application-sidebar-brand|application-sidebar-logo/)
  assert.doesNotMatch(sidebar, /WorkspaceSidebarFooterItem|label="Settings"/)
  assert.match(shared, /accentColor/)
  assert.match(shared, /data-tauri-drag-region/)
  assert.match(config, /"width": 980/)
  assert.match(config, /"height": 680/)
  assert.match(config, /"minWidth": 720/)
  assert.match(rust, /NativeIcon::PreferencesGeneral/)
  assert.match(rust, /"CmdOrCtrl\+,"/)
  assert.match(preferences, /desktop_menu::show_preferences/)
  assert.match(nativePreferences, /NSPanel/)
  assert.match(nativePreferences, /NSSegmentedControl/)
  assert.match(nativePreferences, /gearshape/)
  assert.match(preferences, /NSUserDefaults/)
  assert.match(app, /notesPreferences\s*\.\s*get/)
})

test("every desktop main workspace adopts the shared application sidebar", () => {
  for (const path of [
    "../../Revise/src/features/workspace/standalone-workspace.tsx",
    "../../Reminders/src/App.tsx",
    "../../Quran/src/features/reader/ReaderWorkspace.tsx",
    "../../Nutrition/src/App.tsx",
  ]) {
    assert.match(source(path), /ApplicationSidebarLayout/)
  }
})

test("desktop apps follow the live system appearance", () => {
  for (const path of [
    "../src/main.tsx",
    "../../Nutrition/src/main.tsx",
    "../../Quran/src/main.tsx",
    "../../Reminders/src/main.tsx",
    "../../Revise/src/main.tsx",
  ]) {
    const main = source(path)
    assert.match(main, /defaultTheme="system"/)
    assert.match(main, /systemThemeMigrationVersion="2026-09"/)
    assert.match(main, /<NativeThemeSync \/>/)
  }

  const notesApp = source("../src/App.tsx")
  assert.match(notesApp, /notesPreferences\s*\.set\("system"\)/)
  assert.match(notesApp, /NOTES_NATIVE_SYSTEM_THEME_MIGRATION/)

  const nativeSync = source(
    "../../../../packages/shared-ui/src/components/native-theme-sync.tsx",
  )
  const sharedStyles = source("../../../../packages/shared-ui/src/styles/styles.css")
  const sharedGlobals = source("../../../../packages/shared-ui/src/styles/globals.css")
  assert.match(nativeSync, /setTheme\(theme === "system" \? null : theme\)/)
  assert.match(sharedStyles, /\.light \.application-sidebar-item:hover \{\s*background: #dfdfdd;/)
  assert.match(
    sharedStyles,
    /\.light \.application-sidebar-item\[data-active\] \{[\s\S]*color: #ffffff;/,
  )
  assert.match(
    sharedStyles,
    /\.light \.workspace-library-main \{\s*background: #f5f5f4 !important;\s*color: #27272a !important;/,
  )
  assert.match(sharedStyles, /\.light \.workspace-library-toolbar-title h1,/)
  assert.match(
    sharedStyles,
    /\.application-sidebar-scroll \{[\s\S]*scrollbar-width: none;/,
  )
  assert.match(
    sharedStyles,
    /\.application-sidebar-scroll::\-webkit-scrollbar \{\s*display: none;/,
  )
  assert.match(
    sharedStyles,
    /\.application-sidebar-item-icon > svg \{\s*width: 21px;\s*height: 21px;/,
  )
  assert.match(
    sharedGlobals,
    /\* \{\s*scrollbar-width: none !important;\s*-ms-overflow-style: none !important;/,
  )
  assert.match(
    sharedGlobals,
    /\.workspace-library-new-button \{\s*color: #ffffff !important;/,
  )
  assert.match(
    sharedStyles,
    /\.application-sidebar-layout\[data-sidebar-collapsed\] \{\s*grid-template-columns: 0 minmax\(0, 1fr\);/,
  )
  assert.match(
    sharedStyles,
    /\.application-sidebar-layout\[data-sidebar-collapsed\][\s\S]*\.workspace-library-toolbar \{\s*padding-left: 118px;/,
  )
  assert.match(sharedStyles, /backdrop-filter: blur\(28px\) saturate\(1\.45\)/)
  assert.match(sharedStyles, /rgb\(236 236 234 \/ 66%\)/)
})

test("desktop controls use SF Symbols while the notebook canvas keeps its classic icons", () => {
  const symbols = source(
    "../../../../packages/shared-ui/src/components/sf-symbols.tsx",
  )
  const sidebar = source(
    "../../../../packages/shared-ui/src/components/application-sidebar.tsx",
  )
  const canvasToolbar = source(
    "../../../../packages/canvas/src/react/canvas-toolbar.tsx",
  )
  const reminders = source("../../Reminders/src/App.tsx")

  assert.match(symbols, /import\.meta\.glob<string>/)
  assert.match(symbols, /data-sf-symbol=\{name\}/)
  assert.match(symbols, /maskType: "alpha"/)
  assert.match(symbols, /createSFSymbol\("CalendarDays"\)/)
  assert.match(sidebar, /components\/sf-symbols/)
  assert.match(canvasToolbar, /lucide-react/)
  assert.match(reminders, /components\/sf-symbols/)
  assert.doesNotMatch(sidebar, /lucide-react/)
  assert.doesNotMatch(canvasToolbar, /components\/sf-symbols/)
  assert.doesNotMatch(reminders, /lucide-react/)
})

test("all cards expose tier editing and notebook covers have settings and library controls", () => {
  const properties = source("../src/components/discrete-properties.tsx")
  const panel = source("../src/components/notebook-panel.tsx")
  const home = source("../src/pages/Home.tsx")
  assert.match(properties, /Edit tiers/)
  assert.match(properties, /propertiesPanel === "hidden"/)
  assert.match(panel, /BookCoverInput/)
  assert.match(home, /Set cover|Replace cover/)
  assert.match(home, /Clear cover/)
  assert.match(home, /coverMediaId/)
})

test("tier previews are revision-keyed and persisted separately", () => {
  const editor = source("../src/components/blank-card-editor-dialog.tsx")
  const regenerator = source("../src/components/card-tier-preview-regenerator.tsx")
  const api = source("../src/api/notebook-data.ts")
  const migration = source(
    "../../../../crates/database/migrations/202609280001_card_tiers.sql",
  )
  assert.match(editor, /captureSnapshot/)
  assert.match(editor, /tierRevision: tier\.revision/)
  assert.match(api, /saveCardTierPreviews/)
  assert.match(regenerator, /const \[tierIndex, setTierIndex\]/)
  assert.match(regenerator, /setTierIndex\(\(index\) => index \+ 1\)/)
  assert.equal(regenerator.match(/<EndlessCanvas\s/g)?.length, 1)
  assert.match(regenerator, /tierRevision: tier\.revision/)
  assert.match(regenerator, /captureSnapshot/)
  assert.match(migration, /CREATE TABLE card_tier_previews/)
  assert.match(migration, /PRIMARY KEY\(document_id, card_id, tier_id\)/)
})
