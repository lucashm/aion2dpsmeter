#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(windows)]
mod app;
#[cfg(windows)]
mod backend;
#[cfg(windows)]
mod model;

#[cfg(windows)]
fn main() -> eframe::Result {
    use eframe::egui;
    let icon =
        eframe::icon_data::from_png_bytes(include_bytes!("../../desktop/aion2-meter-elyos.png"))
            .ok();
    let mut viewport = egui::ViewportBuilder::default()
        .with_inner_size([760.0, 620.0])
        .with_min_inner_size([380.0, 260.0]);
    if let Some(icon) = icon {
        viewport = viewport.with_icon(icon);
    }
    eframe::run_native(
        "AION 2 Meter",
        eframe::NativeOptions {
            viewport,
            ..Default::default()
        },
        Box::new(|cc| Ok(Box::new(app::App::new(cc)))),
    )
}

#[cfg(not(windows))]
fn main() {
    eprintln!("This frontend is for Windows. On Linux use scripts/install.sh.");
}
