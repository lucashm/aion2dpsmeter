//! Independent native widgets; only reads the parent's private pipe, never captures.
use crate::{backend, model::State, preferences::Preferences, session::Notice};
use eframe::egui::{
    self, Color32, RichText, ViewportBuilder, ViewportCommand, ViewportId, WindowLevel,
};
use serde::Deserialize;
use serde_json::json;
use std::io::BufRead;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc::Receiver,
};

#[derive(Clone, Default, Deserialize)]
#[serde(default)]
struct Frame {
    state: State,
    preferences: Preferences,
    notice: Option<Notice>,
    locked: bool,
}

struct Host {
    frame: Arc<Mutex<Frame>>,
    closed: Arc<AtomicBool>,
    hotkey: Receiver<backend::Hotkey>,
    last_status: (usize, bool),
}

impl Host {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = Color32::TRANSPARENT;
        cc.egui_ctx.set_visuals(visuals);
        crate::fonts::install(&cc.egui_ctx);
        let frame = Arc::new(Mutex::new(Frame::default()));
        let shared = frame.clone();
        let closed = Arc::new(AtomicBool::new(false));
        let done = closed.clone();
        let ctx = cc.egui_ctx.clone();
        std::thread::spawn(move || {
            for line in std::io::stdin().lock().lines() {
                let Ok(line) = line else { break };
                if let Ok(value) = serde_json::from_str::<Frame>(&line) {
                    *shared.lock().unwrap_or_else(|e| e.into_inner()) = value;
                    ctx.request_repaint();
                }
            }
            done.store(true, Ordering::Release);
            ctx.request_repaint();
        });
        Self {
            frame,
            closed,
            hotkey: backend::hotkey(cc.egui_ctx.clone()),
            last_status: (0, false),
        }
    }
}

impl eframe::App for Host {
    fn clear_color(&self, _: &egui::Visuals) -> [f32; 4] {
        [0.0; 4]
    }
    fn update(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        if self.closed.load(Ordering::Acquire) {
            ctx.send_viewport_cmd(ViewportCommand::Close);
            return;
        }
        while let Ok(event) = self.hotkey.try_recv() {
            match event {
                backend::Hotkey::Ready => println!("{}", json!({"type":"hotkeyReady"})),
                backend::Hotkey::Toggle => println!("{}", json!({"type":"toggleLock"})),
                backend::Hotkey::Error(error) => {
                    println!("{}", json!({"type":"hotkeyError","error":error}))
                }
            }
        }
        let frame = self.frame.lock().unwrap_or_else(|e| e.into_inner()).clone();
        let status = native_status(frame.locked);
        if status != self.last_status {
            println!(
                "{}",
                json!({"type":"overlayStatus","windows":status.0,"passthrough":status.1})
            );
            self.last_status = status;
        }
        let expected = frame
            .preferences
            .widgets
            .iter()
            .filter(|w| w.enabled)
            .count();
        if status.0 != expected || status.1 != frame.locked {
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
        }
        let monitor = ctx
            .input(|i| i.viewport().monitor_size)
            .unwrap_or(egui::vec2(1920.0, 1080.0));
        for widget in frame.preferences.widgets.iter().filter(|w| w.enabled) {
            let id = widget.id.clone();
            let scale = f32::from(frame.preferences.scale) / 100.0;
            let size = match id.as_str() {
                "meter" => egui::vec2(360.0, 220.0),
                "boss" => egui::vec2(400.0, 86.0),
                "ping" => egui::vec2(120.0, 48.0),
                _ => egui::vec2(360.0, 80.0),
            } * scale;
            let pos = egui::pos2(
                widget.x * (monitor.x - size.x).max(0.0),
                widget.y * (monitor.y - size.y).max(0.0),
            );
            let builder = ViewportBuilder::default()
                .with_title(format!("Daevalog · {id}"))
                .with_inner_size(size)
                .with_position(pos)
                .with_decorations(false)
                .with_resizable(false)
                .with_transparent(true)
                .with_taskbar(false)
                .with_active(false)
                .with_mouse_passthrough(frame.locked)
                .with_window_level(WindowLevel::AlwaysOnTop);
            let data = frame.clone();
            ctx.show_viewport_deferred(ViewportId::from_hash_of(&id), builder, move |ctx, _| {
                ctx.set_pixels_per_point(ctx.native_pixels_per_point().unwrap_or(1.0) * scale);
                let alpha = (f32::from(data.preferences.opacity) * 2.55) as u8;
                let panel = egui::Frame::NONE
                    .fill(Color32::from_rgba_unmultiplied(19, 29, 36, alpha))
                    .stroke(egui::Stroke::new(1.0_f32, Color32::from_rgb(49, 79, 83)))
                    .corner_radius(5)
                    .inner_margin(12);
                egui::CentralPanel::default().frame(panel).show(ctx, |ui| {
                    ui.visuals_mut().override_text_color = Some(Color32::from_rgb(225, 236, 238));
                    let header = ui.add(
                        egui::Label::new(
                            RichText::new(match id.as_str() {
                                "meter" => "DAEVALOG · DPS",
                                "boss" => "TARGET HEALTH",
                                "ping" => "LATENCY",
                                _ => "EVENT REMINDERS",
                            })
                            .size(10.0)
                            .color(Color32::from_rgb(120, 219, 204)),
                        )
                        .sense(egui::Sense::drag()),
                    );
                    if !data.locked && header.drag_started() {
                        ctx.send_viewport_cmd(ViewportCommand::StartDrag);
                    }
                    match id.as_str() {
                        "meter" => {
                            if data.state.players.is_empty() {
                                ui.label("Waiting for combat");
                            }
                            for (i, player) in data.state.players.iter().take(6).enumerate() {
                                ui.horizontal(|ui| {
                                    ui.label(format!("{}  {}", i + 1, player.name));
                                    ui.with_layout(
                                        egui::Layout::right_to_left(egui::Align::Center),
                                        |ui| {
                                            ui.strong(crate::model::number(player.dps));
                                        },
                                    );
                                });
                                ui.add(
                                    egui::ProgressBar::new((player.share / 100.0) as f32)
                                        .desired_height(3.0)
                                        .fill(Color32::from_rgb(100, 181, 174)),
                                );
                            }
                        }
                        "boss" => {
                            if let Some(target) = &data.state.target {
                                ui.label(&target.name);
                                if target.max_hp > 0 && target.current_hp >= 0 {
                                    ui.add(
                                        egui::ProgressBar::new(
                                            (target.current_hp as f64 / target.max_hp as f64)
                                                .clamp(0.0, 1.0)
                                                as f32,
                                        )
                                        .fill(Color32::from_rgb(120, 219, 204)),
                                    );
                                } else {
                                    ui.small("Waiting for an HP reading");
                                }
                            } else {
                                ui.label("Waiting for a target");
                            }
                        }
                        "ping" => {
                            ui.label(
                                data.state
                                    .ping_ms
                                    .map(|p| format!("{p} ms"))
                                    .unwrap_or("— ms".into()),
                            );
                        }
                        _ => {
                            ui.label(data.notice.as_ref().map(|n| n.text.as_str()).unwrap_or(
                                if data.locked {
                                    "No active reminders"
                                } else {
                                    "Your event and cube alerts appear here"
                                },
                            ));
                        }
                    }
                });
            });
        }
    }
}

fn native_status(locked: bool) -> (usize, bool) {
    use windows_sys::Win32::Foundation::{BOOL, HWND, LPARAM};
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GWL_EXSTYLE, GetWindowLongPtrW, GetWindowTextW, GetWindowThreadProcessId,
        IsWindowVisible, SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER,
        SetWindowLongPtrW, SetWindowPos, WS_EX_NOACTIVATE, WS_EX_TRANSPARENT,
    };
    unsafe extern "system" fn visit(hwnd: HWND, data: LPARAM) -> BOOL {
        // SAFETY: EnumWindows calls this synchronously with our valid Vec pointer.
        unsafe {
            let mut pid = 0;
            GetWindowThreadProcessId(hwnd, &mut pid);
            if pid == std::process::id() && IsWindowVisible(hwnd) != 0 {
                let mut title = [0_u16; 128];
                let len = GetWindowTextW(hwnd, title.as_mut_ptr(), title.len() as i32);
                if !String::from_utf16_lossy(&title[..len as usize]).starts_with("Daevalog · ") {
                    return 1;
                }
                let (styles, locked) = &mut *(data as *mut (Vec<bool>, bool));
                let original = GetWindowLongPtrW(hwnd, GWL_EXSTYLE) as u32;
                let next = if *locked {
                    original | WS_EX_NOACTIVATE
                } else {
                    original & !WS_EX_NOACTIVATE
                };
                if next != original {
                    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, next as isize);
                    SetWindowPos(
                        hwnd,
                        std::ptr::null_mut(),
                        0,
                        0,
                        0,
                        0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
                    );
                }
                styles.push(next & WS_EX_TRANSPARENT != 0);
            }
        }
        1
    }
    let mut result = (Vec::<bool>::new(), locked);
    // SAFETY: callback pointer and stack allocation stay valid until enumeration returns.
    unsafe {
        EnumWindows(Some(visit), &mut result as *mut _ as LPARAM);
    }
    (
        result.0.len(),
        !result.0.is_empty() && result.0.iter().all(|p| *p),
    )
}

pub fn run() -> eframe::Result {
    eframe::run_native(
        "Daevalog overlay host",
        eframe::NativeOptions {
            viewport: ViewportBuilder::default()
                .with_visible(false)
                .with_taskbar(false),
            persist_window: false,
            ..Default::default()
        },
        Box::new(|cc| Ok(Box::new(Host::new(cc)))),
    )
}
