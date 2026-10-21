use crate::session::{Action, Session, Snapshot};
use tauri::{
    Manager,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};

#[tauri::command]
fn snapshot(session: tauri::State<'_, Session>) -> Snapshot {
    session.snapshot()
}

#[tauri::command]
async fn act(app: tauri::AppHandle, action: Action) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || app.state::<Session>().act(action))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
fn window_action(window: tauri::WebviewWindow, action: &str) -> Result<(), String> {
    match action {
        "minimize" => window.minimize(),
        "maximize" => {
            if window.is_maximized().map_err(|e| e.to_string())? {
                window.unmaximize()
            } else {
                window.maximize()
            }
        }
        "hide" => window.hide(),
        "drag" => window.start_dragging(),
        "quit" => {
            window.app_handle().exit(0);
            Ok(())
        }
        _ => return Err("Unknown window action".into()),
    }
    .map_err(|e| e.to_string())
}

#[cfg(feature = "ui-smoke")]
#[tauri::command]
fn smoke_report(
    app: tauri::AppHandle,
    report: serde_json::Value,
    complete: Option<bool>,
) -> Result<(), String> {
    let path =
        std::env::var_os("AION2_COMPANION_SMOKE_REPORT").ok_or("Smoke output is not configured")?;
    let complete = complete.unwrap_or(true);
    let path = std::path::PathBuf::from(path);
    std::fs::write(
        if complete {
            path
        } else {
            path.with_extension("ready.json")
        },
        report.to_string(),
    )
    .map_err(|e| e.to_string())?;
    if complete {
        app.exit(0);
    }
    Ok(())
}

pub fn run() -> tauri::Result<()> {
    let builder = tauri::Builder::default()
        .manage(Session::new())
        .invoke_handler(tauri::generate_handler![snapshot, act, window_action]);
    #[cfg(feature = "ui-smoke")]
    let builder = builder.invoke_handler(tauri::generate_handler![
        snapshot,
        act,
        window_action,
        smoke_report
    ]);
    let app = builder
        .setup(|app| {
            let window =
                tauri::WebviewWindowBuilder::from_config(app, &app.config().app.windows[0])?
                    .on_navigation(|url| {
                    matches!((url.scheme(), url.host_str()), ("tauri", Some("localhost")) | ("http" | "https", Some("tauri.localhost")))
                        || (cfg!(debug_assertions) && matches!(url.host_str(), Some("localhost" | "127.0.0.1")) && url.port() == Some(5173))
                    });
            #[cfg(feature = "ui-smoke")]
            let window = if let Ok(replay) = std::env::var("AION2_COMPANION_SMOKE_REPLAY") {
                window.initialization_script(format!(
                    "window.__DAEVALOG_SMOKE__={};",
                    serde_json::json!({"replay":replay, "holdMs":std::env::var("AION2_COMPANION_SMOKE_HOLD_MS").ok().and_then(|s| s.parse::<u64>().ok()).unwrap_or(0).min(30_000)})
                ))
            } else {
                window
            };
            window.build()?;
            let show = MenuItem::with_id(app, "show", "Open Daevalog", true, None::<&str>)?;
            let hide =
                MenuItem::with_id(app, "overlays", "Show / hide overlays", true, None::<&str>)?;
            let unlock = MenuItem::with_id(app, "unlock", "Unlock overlays", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Daevalog", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &hide, &unlock, &quit])?;
            let icon = tauri::image::Image::from_bytes(include_bytes!(
                "../../desktop/aion2-meter-elyos.png"
            ))?;
            TrayIconBuilder::new()
                .icon(icon)
                .tooltip("Daevalog · AION 2 companion")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    id @ ("overlays" | "unlock") => {
                        let app = app.clone();
                        let unlock = id == "unlock";
                        std::thread::spawn(move || {
                            let session = app.state::<Session>();
                            if unlock {
                                let _ = session.act(Action::LockOverlay { locked: false });
                            } else {
                                let mut preferences = session.snapshot().preferences;
                                preferences.overlay_visible = !preferences.overlay_visible;
                                let _ = session.act(Action::Preferences { preferences });
                            }
                        });
                    }
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .build(tauri::generate_context!())?;
    app.run(|app, event| {
        if matches!(event, tauri::RunEvent::Exit) {
            app.state::<Session>().shutdown();
        }
    });
    Ok(())
}
