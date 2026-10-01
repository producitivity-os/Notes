use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum NotesAppearance {
    System,
    Light,
    Dark,
}

impl NotesAppearance {
    fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }

    fn from_str(value: &str) -> Self {
        match value {
            "system" => Self::System,
            "light" => Self::Light,
            _ => Self::Dark,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotesPreferences {
    pub appearance: NotesAppearance,
    pub initialized: bool,
}

fn emit_appearance(app: &AppHandle, appearance: NotesAppearance) -> Result<(), String> {
    app.emit("notes:theme-changed", appearance.as_str())
        .map_err(|error| error.to_string())
}

#[cfg(target_os = "macos")]
mod platform {
    use objc2::rc::Retained;
    use objc2_foundation::{NSString, NSUserDefaults};
    use tauri::AppHandle;

    use super::{emit_appearance, NotesAppearance, NotesPreferences};

    const APPEARANCE_KEY: &str = "productivity.notes.appearance";

    fn key() -> Retained<NSString> {
        NSString::from_str(APPEARANCE_KEY)
    }

    pub fn get() -> NotesPreferences {
        let defaults = NSUserDefaults::standardUserDefaults();
        let key = key();
        let stored = defaults.stringForKey(&key);
        NotesPreferences {
            appearance: stored
                .as_ref()
                .map(|value| NotesAppearance::from_str(&value.to_string()))
                .unwrap_or(NotesAppearance::System),
            initialized: stored.is_some(),
        }
    }

    pub fn set(app: &AppHandle, appearance: NotesAppearance) -> Result<(), String> {
        let defaults = NSUserDefaults::standardUserDefaults();
        let key = key();
        let value = NSString::from_str(appearance.as_str());
        unsafe { defaults.setObject_forKey(Some(&value), &key) };
        emit_appearance(app, appearance)
    }

    pub fn show(app: &AppHandle) -> Result<(), String> {
        desktop_menu::show_preferences(app, "Notes")
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use std::sync::{LazyLock, Mutex};

    use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

    use super::{emit_appearance, NotesAppearance, NotesPreferences};

    static APPEARANCE: LazyLock<Mutex<Option<NotesAppearance>>> =
        LazyLock::new(|| Mutex::new(None));

    pub fn get() -> NotesPreferences {
        let appearance = APPEARANCE.lock().ok().and_then(|value| *value);
        NotesPreferences {
            appearance: appearance.unwrap_or(NotesAppearance::System),
            initialized: appearance.is_some(),
        }
    }

    pub fn set(app: &AppHandle, appearance: NotesAppearance) -> Result<(), String> {
        *APPEARANCE
            .lock()
            .map_err(|_| "Notes preferences are unavailable".to_owned())? = Some(appearance);
        emit_appearance(app, appearance)
    }

    pub fn show(app: &AppHandle) -> Result<(), String> {
        if let Some(window) = app.get_webview_window("notes-preferences") {
            window.show().map_err(|error| error.to_string())?;
            return window.set_focus().map_err(|error| error.to_string());
        }
        WebviewWindowBuilder::new(
            app,
            "notes-preferences",
            WebviewUrl::App("index.html?notesPreferences=1".into()),
        )
        .title("Notes Settings")
        .inner_size(520.0, 280.0)
        .resizable(false)
        .build()
        .map(|_| ())
        .map_err(|error| error.to_string())
    }
}

pub fn get() -> NotesPreferences {
    platform::get()
}

pub fn set(app: &AppHandle, appearance: NotesAppearance) -> Result<(), String> {
    platform::set(app, appearance)
}

pub fn show(app: &AppHandle) -> Result<(), String> {
    platform::show(app)
}
