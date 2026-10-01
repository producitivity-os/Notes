use app_core::{
    AppActivity, AppActivityTarget, CanvasDocument, CanvasDocumentSummary, CanvasType,
    MediaDataInput, MediaEntry, MediaImportResult, MediaListQuery, MediaPage, PersonRecord,
    PluginInstallation, SaveCanvasInput, SaveCardTierPreviewInput, SavePersonInput,
    ServiceSettings, WorkflowDocumentKind,
};
use data_client::DataClient;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io::{Read, Seek, SeekFrom},
    path::{Component, Path, PathBuf},
    sync::Mutex,
};
mod preferences;

use tauri::{
    http::{header, Method, Request as HttpRequest, Response as HttpResponse, StatusCode},
    menu::{IconMenuItemBuilder, MenuBuilder, MenuItemBuilder, NativeIcon, SubmenuBuilder},
    AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder,
    WindowEvent,
};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_opener::OpenerExt;

struct AppState {
    client: Option<DataClient>,
    configured_settings: Option<ServiceSettings>,
    config_error: Option<String>,
    initial_navigation: Mutex<Option<InitialNavigation>>,
    card_editor_sessions: Mutex<HashMap<String, CardEditorSession>>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InitialNavigation {
    notebook_id: String,
    object_id: Option<String>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CardEditorSession {
    session_id: String,
    notebook_id: String,
    notebook_title: String,
    card_id: String,
    tiers: serde_json::Value,
    #[serde(skip_serializing)]
    parent_label: String,
    #[serde(skip_serializing)]
    editor_label: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CardEditorLifecycle {
    session_id: String,
    notebook_id: String,
    open: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenCardEditorInput {
    notebook_id: String,
    notebook_title: String,
    card_id: String,
    tiers: serde_json::Value,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CardEditorSaveRequest {
    session_id: String,
    request_id: String,
    card_id: String,
    tiers: serde_json::Value,
    previews: serde_json::Value,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CardEditorSaveResult {
    session_id: String,
    request_id: String,
    succeeded: bool,
    error: Option<String>,
}

#[tauri::command]
fn get_notes_preferences() -> preferences::NotesPreferences {
    preferences::get()
}

#[tauri::command]
fn set_notes_preferences(
    appearance: preferences::NotesAppearance,
    app: AppHandle,
) -> Result<(), String> {
    preferences::set(&app, appearance)
}

impl AppState {
    fn client(&self) -> Result<DataClient, String> {
        self.client.clone().ok_or_else(|| {
            self.config_error
                .clone()
                .unwrap_or_else(|| "data service is not configured".into())
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DataServiceStatus {
    connected: bool,
    configured_settings: Option<ServiceSettings>,
    active_settings: Option<ServiceSettings>,
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NotebookPatch {
    title: Option<String>,
    project: Option<String>,
    icon: Option<String>,
    starred: Option<bool>,
    cover_media_id: Option<Option<String>>,
}

#[tauri::command]
async fn data_service_status(state: State<'_, AppState>) -> Result<DataServiceStatus, String> {
    let Ok(client) = state.client() else {
        return Ok(DataServiceStatus {
            connected: false,
            configured_settings: state.configured_settings.clone(),
            active_settings: None,
            error: state.config_error.clone(),
        });
    };
    match client.settings().await {
        Ok(settings) => Ok(DataServiceStatus {
            connected: true,
            configured_settings: state.configured_settings.clone(),
            active_settings: Some(settings),
            error: None,
        }),
        Err(error) => Ok(DataServiceStatus {
            connected: false,
            configured_settings: state.configured_settings.clone(),
            active_settings: None,
            error: Some(error.to_string()),
        }),
    }
}

#[tauri::command]
fn initial_navigation(state: State<'_, AppState>) -> Option<InitialNavigation> {
    state.initial_navigation.lock().ok()?.take()
}

#[tauri::command]
async fn list_notebooks(state: State<'_, AppState>) -> Result<Vec<CanvasDocumentSummary>, String> {
    state
        .client()?
        .list_notebooks()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn get_notebook(
    id: String,
    state: State<'_, AppState>,
) -> Result<Option<CanvasDocument>, String> {
    let notebook = state
        .client()?
        .get_canvas(id)
        .await
        .map_err(|error| error.to_string())?;
    Ok(notebook.filter(|document| document.summary.canvas_type == CanvasType::Notebook))
}

#[tauri::command]
async fn save_notebook(
    mut input: SaveCanvasInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<CanvasDocumentSummary, String> {
    input.canvas_type = CanvasType::Notebook;
    let saved = state
        .client()?
        .save_canvas(input)
        .await
        .map_err(|error| error.to_string())?;
    app.emit("notes:notebooks-changed", &saved)
        .map_err(|error| error.to_string())?;
    Ok(saved)
}

#[tauri::command]
async fn update_notebook(
    id: String,
    patch: NotebookPatch,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<Option<CanvasDocumentSummary>, String> {
    let Some(document) = state
        .client()?
        .get_canvas(id)
        .await
        .map_err(|error| error.to_string())?
    else {
        return Ok(None);
    };
    if document.summary.canvas_type != CanvasType::Notebook {
        return Ok(None);
    }
    let input = SaveCanvasInput {
        id: document.summary.id,
        title: patch.title.unwrap_or(document.summary.title),
        project: patch.project.unwrap_or(document.summary.project),
        canvas_type: CanvasType::Notebook,
        workflow_kind: WorkflowDocumentKind::Workflow,
        icon: patch.icon.unwrap_or(document.summary.icon),
        starred: patch.starred.unwrap_or(document.summary.starred),
        cover_media_id: patch
            .cover_media_id
            .unwrap_or(document.summary.cover_media_id),
        expected_revision: Some(document.summary.revision),
        canvas: document.canvas,
    };
    let saved = state
        .client()?
        .save_canvas(input)
        .await
        .map_err(|error| error.to_string())?;
    app.emit("notes:notebooks-changed", &saved)
        .map_err(|error| error.to_string())?;
    Ok(Some(saved))
}

#[tauri::command]
async fn delete_notebook(
    id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    let Some(document) = state
        .client()?
        .get_canvas(id.clone())
        .await
        .map_err(|error| error.to_string())?
    else {
        return Ok(false);
    };
    if document.summary.canvas_type != CanvasType::Notebook {
        return Ok(false);
    }
    let deleted = state
        .client()?
        .delete_canvas(id)
        .await
        .map_err(|error| error.to_string())?;
    if deleted {
        app.emit("notes:notebooks-changed", ())
            .map_err(|error| error.to_string())?;
    }
    Ok(deleted)
}

#[tauri::command]
async fn save_notebook_preview(
    id: String,
    data_url: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    let saved = state
        .client()?
        .save_canvas_preview(id, data_url)
        .await
        .map_err(|error| error.to_string())?;
    if saved {
        app.emit("notes:notebooks-changed", ())
            .map_err(|error| error.to_string())?;
    }
    Ok(saved)
}

#[tauri::command]
async fn save_card_tier_previews(
    previews: Vec<SaveCardTierPreviewInput>,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    state
        .client()?
        .save_card_tier_previews(previews)
        .await
        .map_err(|error| error.to_string())
}

fn notebook_window_label(id: &str) -> String {
    format!(
        "notebook-{}",
        id.chars()
            .filter(|character| character.is_ascii_alphanumeric() || *character == '-')
            .collect::<String>()
    )
}

fn card_editor_window_label(id: &str) -> String {
    format!(
        "card-editor-{}",
        id.chars()
            .filter(|character| character.is_ascii_alphanumeric() || *character == '-')
            .collect::<String>()
    )
}

fn emit_card_editor_lifecycle(app: &AppHandle, session: &CardEditorSession, open: bool) {
    if let Some(parent) = app.get_webview_window(&session.parent_label) {
        let _ = parent.emit(
            "notes:card-editor-lifecycle",
            CardEditorLifecycle {
                session_id: session.session_id.clone(),
                notebook_id: session.notebook_id.clone(),
                open,
            },
        );
    }
}

fn restore_card_editor_parent(app: &AppHandle, session: &CardEditorSession) {
    if let Some(parent) = app.get_webview_window(&session.parent_label) {
        emit_card_editor_lifecycle(app, session, false);
        let _ = parent.show();
        let _ = parent.set_focus();
    }
}

#[tauri::command]
fn open_card_editor_window(
    input: OpenCardEditorInput,
    parent: WebviewWindow,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let existing = state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .values()
        .find(|session| session.notebook_id == input.notebook_id)
        .cloned();
    if let Some(existing) = existing {
        if let Some(editor) = app.get_webview_window(&existing.editor_label) {
            emit_card_editor_lifecycle(&app, &existing, true);
            editor.show().map_err(|error| error.to_string())?;
            editor.set_focus().map_err(|error| error.to_string())?;
            return Ok(existing.session_id);
        }
    }

    let session_id = uuid::Uuid::now_v7().to_string();
    let editor_label = card_editor_window_label(&input.notebook_id);
    let session = CardEditorSession {
        session_id: session_id.clone(),
        notebook_id: input.notebook_id,
        notebook_title: input.notebook_title,
        card_id: input.card_id,
        tiers: input.tiers,
        parent_label: parent.label().to_owned(),
        editor_label: editor_label.clone(),
    };
    state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .insert(session_id.clone(), session.clone());

    let route = format!("index.html?cardEditorSession={session_id}");
    let editor_result =
        WebviewWindowBuilder::new(&app, editor_label, WebviewUrl::App(route.into()))
            .parent(&parent)
            .and_then(|builder| {
                builder
                    .title(format!("Edit Card — {}", session.notebook_title))
                    .inner_size(1000.0, 760.0)
                    .min_inner_size(760.0, 520.0)
                    .decorations(true)
                    .build()
            });
    let editor = match editor_result {
        Ok(window) => window,
        Err(error) => {
            let _ = state
                .card_editor_sessions
                .lock()
                .map(|mut sessions| sessions.remove(&session_id));
            return Err(error.to_string());
        }
    };
    emit_card_editor_lifecycle(&app, &session, true);
    let cleanup_app = app.clone();
    let cleanup_session_id = session_id.clone();
    let cleanup_session = session.clone();
    editor.on_window_event(move |event| {
        if !matches!(event, WindowEvent::Destroyed) {
            return;
        }
        let state = cleanup_app.state::<AppState>();
        let _ = state
            .card_editor_sessions
            .lock()
            .ok()
            .and_then(|mut sessions| sessions.remove(&cleanup_session_id));
        restore_card_editor_parent(&cleanup_app, &cleanup_session);
    });
    Ok(session_id)
}

#[tauri::command]
fn card_editor_session(
    session_id: String,
    window: WebviewWindow,
    state: State<'_, AppState>,
) -> Result<CardEditorSession, String> {
    let session = state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .get(&session_id)
        .cloned()
        .ok_or_else(|| "card editor session does not exist".to_owned())?;
    if session.editor_label != window.label() {
        return Err("card editor session belongs to another window".to_owned());
    }
    Ok(session)
}

#[tauri::command]
fn request_card_editor_save(
    input: CardEditorSaveRequest,
    window: WebviewWindow,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let session = state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .get(&input.session_id)
        .cloned()
        .ok_or_else(|| "card editor session does not exist".to_owned())?;
    if session.editor_label != window.label() || session.card_id != input.card_id {
        return Err("card editor save does not match its session".to_owned());
    }
    app.get_webview_window(&session.parent_label)
        .ok_or_else(|| "notebook window is no longer available".to_owned())?
        .emit("notes:card-editor-save-request", input)
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn resolve_card_editor_save(
    input: CardEditorSaveResult,
    window: WebviewWindow,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let session = state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .get(&input.session_id)
        .cloned()
        .ok_or_else(|| "card editor session does not exist".to_owned())?;
    if session.parent_label != window.label() {
        return Err("save result came from another notebook window".to_owned());
    }
    app.get_webview_window(&session.editor_label)
        .ok_or_else(|| "card editor window is no longer available".to_owned())?
        .emit("notes:card-editor-save-result", input)
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn close_card_editor_session(
    session_id: String,
    window: WebviewWindow,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let session = state
        .card_editor_sessions
        .lock()
        .map_err(|_| "card editor session lock is unavailable".to_owned())?
        .remove(&session_id)
        .ok_or_else(|| "card editor session does not exist".to_owned())?;
    if session.editor_label != window.label() {
        state
            .card_editor_sessions
            .lock()
            .map_err(|_| "card editor session lock is unavailable".to_owned())?
            .insert(session_id, session);
        return Err("card editor session belongs to another window".to_owned());
    }
    restore_card_editor_parent(&app, &session);
    Ok(())
}

fn focused_notebook_window(app: &AppHandle) -> Option<WebviewWindow> {
    app.webview_windows().into_values().find(|window| {
        window.label().starts_with("notebook-") && window.is_focused().unwrap_or(false)
    })
}

fn emit_to_focused_notebook(app: &AppHandle, event: &str) {
    if let Some(window) = focused_notebook_window(app) {
        let _ = window.emit(event, ());
    }
}

fn set_notebook_menu_enabled(app: &AppHandle, enabled: bool) {
    let Some(menu) = app.menu() else {
        return;
    };
    for id in [
        "toggle_notebook_favorite",
        "export_notebook",
        "toggle_notebook_panel",
    ] {
        if let Some(item) = menu.get(id).and_then(|item| item.as_menuitem().cloned()) {
            let _ = item.set_enabled(enabled);
        }
    }
}

fn show_notebook_window(
    app: &AppHandle,
    id: &str,
    title: &str,
    focus_object_id: Option<&str>,
) -> Result<(), String> {
    let label = notebook_window_label(id);
    if let Some(window) = app.get_webview_window(&label) {
        window.show().map_err(|error| error.to_string())?;
        window.set_focus().map_err(|error| error.to_string())?;
        if let Some(object_id) = focus_object_id {
            window
                .emit("notes:focus-object", object_id)
                .map_err(|error| error.to_string())?;
        }
        return Ok(());
    }
    let route = focus_object_id
        .map(|object_id| format!("index.html?notebookId={id}&focus={object_id}"))
        .unwrap_or_else(|| format!("index.html?notebookId={id}"));
    WebviewWindowBuilder::new(app, label, WebviewUrl::App(route.into()))
        .title(format!("{title} — Notes"))
        .inner_size(1280.0, 820.0)
        .min_inner_size(760.0, 520.0)
        .decorations(true)
        .title_bar_style(tauri::TitleBarStyle::Overlay)
        .hidden_title(true)
        .build()
        .map_err(|error| error.to_string())?;
    Ok(())
}

#[tauri::command]
async fn open_notebook_window(
    id: String,
    title: String,
    focus_object_id: Option<String>,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let document = state
        .client()?
        .get_canvas(id.clone())
        .await
        .map_err(|error| error.to_string())?;
    if !matches!(document, Some(ref document) if document.summary.canvas_type == CanvasType::Notebook)
    {
        return Err("notebook does not exist".into());
    }
    show_notebook_window(&app, &id, &title, focus_object_id.as_deref())
}

#[tauri::command]
fn focus_notes_home(app: AppHandle) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Notes Home is unavailable".to_owned())?;
    window.show().map_err(|error| error.to_string())?;
    window.set_focus().map_err(|error| error.to_string())
}

async fn dispatch_app_activity(
    app: &AppHandle,
    _client: &DataClient,
    activity: AppActivity,
) -> Result<(), String> {
    if !activity.is_valid() {
        return Err("invalid app activity".into());
    }
    #[cfg(debug_assertions)]
    {
        let _ = app;
        _client
            .publish_app_activity(activity)
            .await
            .map(|_| ())
            .map_err(|error| {
                format!("Revise source host is unavailable. Run `yarn desktop:dev`. {error}")
            })
    }
    #[cfg(not(debug_assertions))]
    {
        app.opener()
            .open_url(activity.url(), None::<&str>)
            .map_err(|error| error.to_string())
    }
}

#[tauri::command]
async fn open_revise_for_notebook(
    id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let document = state
        .client()?
        .get_canvas(id.clone())
        .await
        .map_err(|error| error.to_string())?;
    if !matches!(document, Some(ref document) if document.summary.canvas_type == CanvasType::Notebook)
    {
        return Err("notebook does not exist".into());
    }
    dispatch_app_activity(
        &app,
        &state.client()?,
        AppActivity::ReviseNotebookReview { notebook_id: id },
    )
    .await
}

#[tauri::command]
async fn list_plugin_installations(
    state: State<'_, AppState>,
) -> Result<Vec<PluginInstallation>, String> {
    state
        .client()?
        .list_plugin_installations()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn set_plugin_installed(
    plugin_id: String,
    installed: bool,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<PluginInstallation, String> {
    let result = state
        .client()?
        .set_plugin_installed(plugin_id, installed)
        .await
        .map_err(|error| error.to_string())?;
    app.emit("notes:plugins-changed", &result)
        .map_err(|error| error.to_string())?;
    Ok(result)
}

#[tauri::command]
async fn list_notes_persons(
    query: Option<String>,
    state: State<'_, AppState>,
) -> Result<Vec<PersonRecord>, String> {
    state
        .client()?
        .list_persons(query)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn save_notes_person(
    input: SavePersonInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<PersonRecord, String> {
    let person = state
        .client()?
        .save_person(input)
        .await
        .map_err(|error| error.to_string())?;
    app.emit("notes:persons-changed", &person)
        .map_err(|error| error.to_string())?;
    Ok(person)
}

#[tauri::command]
async fn import_notebook_media(
    input: MediaDataInput,
    state: State<'_, AppState>,
) -> Result<MediaImportResult, String> {
    let document = state
        .client()?
        .get_canvas(input.canvas_id.clone())
        .await
        .map_err(|error| error.to_string())?;
    if !matches!(document, Some(ref document) if document.summary.canvas_type == CanvasType::Notebook)
    {
        return Err("notebook does not exist".into());
    }
    state
        .client()?
        .import_media_data(input)
        .await
        .map_err(|error| error.to_string())
}

async fn notebook_media_entry(
    id: String,
    state: &State<'_, AppState>,
) -> Result<Option<MediaEntry>, String> {
    let entry = state
        .client()?
        .get_media_entry(id)
        .await
        .map_err(|error| error.to_string())?;
    let Some(entry) = entry else {
        return Ok(None);
    };
    let notebook = state
        .client()?
        .get_canvas(entry.canvas_id.clone())
        .await
        .map_err(|error| error.to_string())?;
    if !matches!(notebook, Some(ref document) if document.summary.canvas_type == CanvasType::Notebook)
    {
        return Err("media does not belong to a notebook".into());
    }
    Ok(Some(entry))
}

#[tauri::command]
async fn list_notebook_media(
    mut query: MediaListQuery,
    state: State<'_, AppState>,
) -> Result<MediaPage, String> {
    query.canvas_type = Some(CanvasType::Notebook);
    state
        .client()?
        .list_media(query)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn import_notebook_media_paths(
    canvas_id: String,
    source_paths: Vec<String>,
    state: State<'_, AppState>,
) -> Result<MediaImportResult, String> {
    let document = state
        .client()?
        .get_canvas(canvas_id.clone())
        .await
        .map_err(|error| error.to_string())?;
    if !matches!(document, Some(ref document) if document.summary.canvas_type == CanvasType::Notebook)
    {
        return Err("notebook does not exist".into());
    }
    state
        .client()?
        .import_media_paths(canvas_id, source_paths)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn get_notebook_media(
    id: String,
    state: State<'_, AppState>,
) -> Result<Option<MediaEntry>, String> {
    notebook_media_entry(id, &state).await
}

#[tauri::command]
async fn delete_notebook_media(id: String, state: State<'_, AppState>) -> Result<bool, String> {
    if notebook_media_entry(id.clone(), &state).await?.is_none() {
        return Ok(false);
    }
    state
        .client()?
        .delete_media(id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn open_notebook_media(
    id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    if notebook_media_entry(id.clone(), &state).await?.is_none() {
        return Err("media entry does not exist".into());
    }
    let storage = state
        .client()?
        .get_media_storage(id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "media entry does not exist".to_owned())?;
    let root = state
        .configured_settings
        .as_ref()
        .map(|settings| PathBuf::from(&settings.media_path))
        .ok_or_else(|| "media storage is not configured".to_owned())?;
    let path = safe_media_path(&root, &storage.storage_key)?;
    app.opener()
        .open_path(path.to_string_lossy(), None::<&str>)
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn reveal_notebook_media(
    id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    if notebook_media_entry(id.clone(), &state).await?.is_none() {
        return Err("media entry does not exist".into());
    }
    let storage = state
        .client()?
        .get_media_storage(id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "media entry does not exist".to_owned())?;
    let root = state
        .configured_settings
        .as_ref()
        .map(|settings| PathBuf::from(&settings.media_path))
        .ok_or_else(|| "media storage is not configured".to_owned())?;
    let path = safe_media_path(&root, &storage.storage_key)?;
    app.opener()
        .reveal_item_in_dir(path)
        .map_err(|error| error.to_string())
}

fn safe_media_path(root: &Path, key: &str) -> Result<PathBuf, String> {
    let relative = Path::new(key);
    if relative.is_absolute()
        || relative
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err("invalid media storage key".into());
    }
    let root = std::fs::canonicalize(root).map_err(|error| error.to_string())?;
    let path = std::fs::canonicalize(root.join(relative)).map_err(|error| error.to_string())?;
    if !path.starts_with(&root) {
        return Err("media path escapes storage root".into());
    }
    Ok(path)
}

fn protocol_response(
    client: DataClient,
    media_root: PathBuf,
    request: HttpRequest<Vec<u8>>,
) -> HttpResponse<Vec<u8>> {
    let segments: Vec<&str> = request
        .uri()
        .path()
        .trim_start_matches('/')
        .split('/')
        .collect();
    if segments.len() != 2 || !matches!(segments[1], "content" | "thumbnail" | "proxy") {
        return response(
            StatusCode::NOT_FOUND,
            "text/plain",
            b"media not found".to_vec(),
        );
    }
    if !matches!(*request.method(), Method::GET | Method::HEAD) {
        return response(StatusCode::METHOD_NOT_ALLOWED, "text/plain", Vec::new());
    }
    let id = segments[0].to_owned();
    let thumbnail = segments[1] == "thumbnail";
    let proxy = segments[1] == "proxy";
    let storage = match tauri::async_runtime::block_on(client.get_media_storage(id)) {
        Ok(Some(storage)) => storage,
        _ => {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain",
                b"media not found".to_vec(),
            )
        }
    };
    let key = if thumbnail {
        storage
            .thumbnail_key
            .as_deref()
            .unwrap_or(&storage.storage_key)
    } else if proxy {
        storage.proxy_key.as_deref().unwrap_or(&storage.storage_key)
    } else {
        &storage.storage_key
    };
    let path = match safe_media_path(&media_root, key) {
        Ok(path) => path,
        Err(_) => {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain",
                b"media not found".to_vec(),
            )
        }
    };
    let mut file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(_) => {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain",
                b"media not found".to_vec(),
            )
        }
    };
    let size = file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
    let content_type = if thumbnail {
        "image/webp"
    } else if proxy && storage.proxy_key.is_some() {
        "video/mp4"
    } else {
        storage.mime_type.as_str()
    };
    let range = request
        .headers()
        .get(header::RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| parse_range(value, size));
    let (status, start, end) = match (request.headers().contains_key(header::RANGE), range) {
        (true, Some((start, end))) => (StatusCode::PARTIAL_CONTENT, start, end),
        (true, None) => {
            return HttpResponse::builder()
                .status(StatusCode::RANGE_NOT_SATISFIABLE)
                .header(header::CONTENT_RANGE, format!("bytes */{size}"))
                .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                .header("Cross-Origin-Resource-Policy", "cross-origin")
                .body(Vec::new())
                .unwrap()
        }
        (false, _) => (StatusCode::OK, 0, size.saturating_sub(1)),
    };
    let length = if size == 0 { 0 } else { end - start + 1 };
    let mut body = Vec::new();
    if *request.method() != Method::HEAD && length > 0 {
        if file.seek(SeekFrom::Start(start)).is_err() {
            return response(StatusCode::INTERNAL_SERVER_ERROR, "text/plain", Vec::new());
        }
        let mut limited = file.take(length);
        if limited.read_to_end(&mut body).is_err() {
            return response(StatusCode::INTERNAL_SERVER_ERROR, "text/plain", Vec::new());
        }
    }
    let mut builder = HttpResponse::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, length.to_string())
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .header("Cross-Origin-Resource-Policy", "cross-origin")
        .header(
            header::CACHE_CONTROL,
            "private, max-age=31536000, immutable",
        );
    if status == StatusCode::PARTIAL_CONTENT {
        builder = builder.header(header::CONTENT_RANGE, format!("bytes {start}-{end}/{size}"));
    }
    builder.body(body).unwrap()
}

fn parse_range(value: &str, size: u64) -> Option<(u64, u64)> {
    let value = value.strip_prefix("bytes=")?;
    if value.contains(',') || size == 0 {
        return None;
    }
    let (start, end) = value.split_once('-')?;
    if start.is_empty() {
        let suffix = end.parse::<u64>().ok()?.min(size);
        return Some((size - suffix, size - 1));
    }
    let start = start.parse::<u64>().ok()?;
    if start >= size {
        return None;
    }
    let end = if end.is_empty() {
        size - 1
    } else {
        end.parse::<u64>().ok()?.min(size - 1)
    };
    (start <= end).then_some((start, end))
}

fn response(status: StatusCode, content_type: &str, body: Vec<u8>) -> HttpResponse<Vec<u8>> {
    HttpResponse::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .header("Cross-Origin-Resource-Policy", "cross-origin")
        .body(body)
        .unwrap()
}

fn show_main_window(app: &AppHandle) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Notes Home is unavailable".to_owned())?;
    window.show().map_err(|error| error.to_string())?;
    window.set_focus().map_err(|error| error.to_string())
}

async fn handle_activity(app: AppHandle, activity: AppActivity) -> Result<(), String> {
    let client = app.state::<AppState>().client()?;
    match activity {
        AppActivity::NotesCard {
            notebook_id,
            object_id,
        } => {
            let document = client
                .get_canvas(notebook_id.clone())
                .await
                .map_err(|error| error.to_string())?
                .filter(|document| document.summary.canvas_type == CanvasType::Notebook)
                .ok_or_else(|| "notebook does not exist".to_owned())?;
            show_notebook_window(
                &app,
                &notebook_id,
                &document.summary.title,
                object_id.as_deref(),
            )
        }
        _ => Err("activity is not handled by Notes".into()),
    }
}

fn dispatch_activity_urls(app: &AppHandle, values: impl IntoIterator<Item = String>) -> bool {
    let activities: Vec<_> = values
        .into_iter()
        .filter_map(|value| AppActivity::parse_url(&value))
        .filter(|activity| activity.target() == AppActivityTarget::Notes)
        .collect();
    let handled = !activities.is_empty();
    for activity in activities {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            let _ = handle_activity(app, activity).await;
        });
    }
    handled
}

fn start_development_activity_host(app: AppHandle, client: DataClient) {
    let instance_id = uuid::Uuid::now_v7().to_string();
    tauri::async_runtime::spawn(async move {
        loop {
            let _ = client
                .register_app_activity_host(AppActivityTarget::Notes, instance_id.clone())
                .await;
            if let Ok(activities) = client
                .claim_app_activities(AppActivityTarget::Notes, instance_id.clone())
                .await
            {
                for envelope in activities {
                    let succeeded = handle_activity(app.clone(), envelope.activity)
                        .await
                        .is_ok();
                    let _ = client
                        .ack_app_activity(envelope.id, instance_id.clone(), succeeded)
                        .await;
                }
            }
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let (client, configured_settings, config_error) = match app_config::ProductivityConfig::load() {
        Ok(config) => {
            let settings = config.service_settings();
            let client = DataClient::new(
                &config.data_service.socket_path,
                config.data_service.max_request_bytes,
            );
            (Some(client), Some(settings), None)
        }
        Err(error) => (None, None, Some(error.to_string())),
    };
    let arguments: Vec<String> = std::env::args().collect();
    let initial_notebook_id = arguments
        .iter()
        .position(|value| value == "--notebook-id")
        .and_then(|index| arguments.get(index + 1))
        .cloned();
    let initial_object_id = arguments
        .iter()
        .position(|value| value == "--object-id")
        .and_then(|index| arguments.get(index + 1))
        .cloned();
    let activity_host = arguments.iter().any(|value| value == "--activity-host");
    let initial_target = initial_notebook_id
        .clone()
        .map(|notebook_id| InitialNavigation {
            notebook_id: notebook_id.clone(),
            object_id: initial_object_id.clone(),
        });
    let legacy_activity = initial_notebook_id.map(|notebook_id| AppActivity::NotesCard {
        notebook_id,
        object_id: initial_object_id,
    });
    let managed_client = client.clone();
    let protocol_client = client.clone();
    let protocol_media_root = configured_settings
        .as_ref()
        .map(|settings| PathBuf::from(&settings.media_path));
    let mut builder = tauri::Builder::default();
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            dispatch_activity_urls(app, args);
        }));
    }
    builder
        .plugin(tauri_plugin_deep_link::init())
        .manage(AppState {
            client,
            configured_settings,
            config_error,
            initial_navigation: Mutex::new(initial_target),
            card_editor_sessions: Mutex::new(HashMap::new()),
        })
        .manage(desktop_menu::NativeMenuState::default())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
            if let Err(error) = desktop_menu::apply_settings_cog_symbol() {
                eprintln!("could not install the Notes Settings menu icon: {error}");
            }
            let handle = app.handle().clone();
            let mut handled = legacy_activity
                .clone()
                .is_some_and(|activity| dispatch_activity_urls(&handle, [activity.url()]));
            if let Some(urls) = app.deep_link().get_current()? {
                handled |=
                    dispatch_activity_urls(&handle, urls.into_iter().map(|url| url.to_string()));
            }
            let event_handle = handle.clone();
            app.deep_link().on_open_url(move |event| {
                dispatch_activity_urls(&event_handle, event.urls().iter().map(ToString::to_string));
            });
            if activity_host {
                if let Some(client) = managed_client.clone() {
                    start_development_activity_host(handle, client);
                }
            } else if !handled {
                show_main_window(&handle).map_err(std::io::Error::other)?;
            }
            Ok(())
        })
        .menu(|app| {
            let settings = IconMenuItemBuilder::with_id("app:settings", "Settings…")
                .native_icon(NativeIcon::PreferencesGeneral)
                .accelerator("CmdOrCtrl+,")
                .build(app)?;
            let toggle_favorite =
                MenuItemBuilder::with_id("toggle_notebook_favorite", "Toggle Favorite")
                    .enabled(false)
                    .build(app)?;
            let export_notebook = MenuItemBuilder::with_id("export_notebook", "Export Notebook…")
                .enabled(false)
                .build(app)?;
            let toggle_panel =
                MenuItemBuilder::with_id("toggle_notebook_panel", "Toggle Notebook Panel")
                    .accelerator("CmdOrCtrl+\\")
                    .enabled(false)
                    .build(app)?;
            let app_menu = SubmenuBuilder::new(app, "Notes")
                .about(None)
                .separator()
                .item(&settings)
                .separator()
                .services()
                .separator()
                .hide()
                .hide_others()
                .separator()
                .quit()
                .build()?;
            let file_menu = SubmenuBuilder::new(app, "File")
                .items(&[&toggle_favorite, &export_notebook])
                .separator()
                .close_window()
                .build()?;
            let edit_menu = SubmenuBuilder::new(app, "Edit")
                .undo()
                .redo()
                .separator()
                .cut()
                .copy()
                .paste()
                .select_all()
                .build()?;
            let view_menu = SubmenuBuilder::new(app, "View")
                .item(&toggle_panel)
                .separator()
                .fullscreen()
                .build()?;
            let window_menu = SubmenuBuilder::new(app, "Window")
                .minimize()
                .maximize()
                .separator()
                .close_window()
                .build()?;
            let help_menu = SubmenuBuilder::new(app, "Help").build()?;
            MenuBuilder::new(app)
                .items(&[
                    &app_menu,
                    &file_menu,
                    &edit_menu,
                    &view_menu,
                    &window_menu,
                    &help_menu,
                ])
                .build()
        })
        .on_menu_event(|app, event| {
            if desktop_menu::handle_menu_event(app, &event) {
                return;
            }
            match event.id().as_ref() {
                "app:settings" => {
                    if let Err(error) = preferences::show(app) {
                        eprintln!("could not open Notes Settings: {error}");
                    }
                }
                "toggle_notebook_favorite" => {
                    emit_to_focused_notebook(app, "notes:native-toggle-favorite")
                }
                "export_notebook" => emit_to_focused_notebook(app, "notes:native-export-notebook"),
                "toggle_notebook_panel" => {
                    emit_to_focused_notebook(app, "notes:native-toggle-notebook-panel")
                }
                _ => {}
            }
        })
        .on_window_event(|window, event| {
            if matches!(event, WindowEvent::Destroyed) {
                desktop_menu::cleanup_window(window.app_handle(), window.label());
            }
            if matches!(event, WindowEvent::Focused(true)) {
                set_notebook_menu_enabled(
                    window.app_handle(),
                    window.label().starts_with("notebook-"),
                );
            }
        })
        .register_asynchronous_uri_scheme_protocol("media", move |_context, request, responder| {
            let client = protocol_client.clone();
            let media_root = protocol_media_root.clone();
            std::thread::spawn(move || {
                let response = match (client, media_root) {
                    (Some(client), Some(media_root)) => {
                        protocol_response(client, media_root, request)
                    }
                    _ => response(
                        StatusCode::SERVICE_UNAVAILABLE,
                        "text/plain",
                        b"media service unavailable".to_vec(),
                    ),
                };
                responder.respond(response);
            });
        })
        .invoke_handler(tauri::generate_handler![
            get_notes_preferences,
            set_notes_preferences,
            data_service_status,
            initial_navigation,
            list_notebooks,
            get_notebook,
            save_notebook,
            update_notebook,
            delete_notebook,
            save_notebook_preview,
            save_card_tier_previews,
            open_notebook_window,
            open_card_editor_window,
            card_editor_session,
            request_card_editor_save,
            resolve_card_editor_save,
            close_card_editor_session,
            desktop_menu::commands::popup_native_context_menu,
            focus_notes_home,
            open_revise_for_notebook,
            list_plugin_installations,
            set_plugin_installed,
            list_notes_persons,
            save_notes_person,
            import_notebook_media,
            list_notebook_media,
            import_notebook_media_paths,
            get_notebook_media,
            delete_notebook_media,
            open_notebook_media,
            reveal_notebook_media,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Notes");
}
