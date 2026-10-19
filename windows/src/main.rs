#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(windows)]
mod app;
#[cfg(windows)]
mod backend;
#[cfg(windows)]
mod companion;
#[cfg(windows)]
mod model;
#[cfg(windows)]
mod overlay_host;
#[cfg(windows)]
mod preferences;
#[cfg(windows)]
mod session;

#[cfg(windows)]
fn legacy() -> eframe::Result {
    use eframe::egui;
    let icon =
        eframe::icon_data::from_png_bytes(include_bytes!("../../desktop/aion2-meter-elyos.png"))
            .ok();
    let mut viewport = egui::ViewportBuilder::default()
        .with_title("Daevalog")
        .with_inner_size([760.0, 620.0])
        .with_min_inner_size([380.0, 260.0]);
    if let Some(icon) = icon {
        viewport = viewport.with_icon(icon);
    }
    eframe::run_native(
        // Keep eframe's storage ID so the display-name change preserves
        // existing window preferences and settings, just as it does on Linux.
        "AION 2 Meter",
        eframe::NativeOptions {
            viewport,
            ..Default::default()
        },
        Box::new(|cc| Ok(Box::new(app::App::new(cc)))),
    )
}

#[cfg(windows)]
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let result = if args.iter().any(|a| a == "--overlay-stdio") {
        overlay_host::run().map_err(|e| e.to_string())
    } else if args.iter().any(|a| a == "--legacy") {
        legacy().map_err(|e| e.to_string())
    } else {
        companion::run().map_err(|e| e.to_string())
    };
    if let Err(error) = result {
        // A GUI executable has no console; keep startup failures reviewable.
        let _ = std::fs::create_dir_all(backend::data_dir());
        let _ = std::fs::write(backend::data_dir().join("startup-error.log"), &error);
        let message: Vec<u16> = format!("Daevalog could not start.\n\n{error}\n\nInstall Microsoft Edge WebView2 Runtime if it is missing.").encode_utf16().chain(Some(0)).collect();
        let title: Vec<u16> = "Daevalog".encode_utf16().chain(Some(0)).collect();
        // SAFETY: valid NUL-terminated UTF-16 strings; no parent window.
        unsafe {
            windows_sys::Win32::UI::WindowsAndMessaging::MessageBoxW(
                std::ptr::null_mut(),
                message.as_ptr(),
                title.as_ptr(),
                0x10,
            );
        }
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("This frontend is for Windows. On Linux use scripts/install.sh.");
}
