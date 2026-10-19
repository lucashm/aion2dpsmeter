use std::sync::mpsc::Receiver;
use std::time::Duration;

use eframe::egui::{self, Color32, RichText, ViewportCommand, WindowLevel};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::backend::{self, Adapter, Backend};
use crate::model::{Fight, Player, Skill, State, number, read_fight};

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct Settings {
    iface: String,
    always_on_top: bool,
    compact: bool,
}

pub struct App {
    settings: Settings,
    backend: Option<Backend>,
    adapters: Vec<Adapter>,
    state: State,
    error: Option<String>,
    tab: usize,
    replay: String,
    fights: Vec<Fight>,
    fight: Option<Fight>,
    fight_skills: Vec<Skill>,
    history_player: Option<i32>,
    pets: Value,
    pet_names: Value,
    cube: Option<String>,
    click_through: bool,
    hotkey_ok: bool,
    hotkey: Receiver<backend::Hotkey>,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        cc.egui_ctx.set_visuals(egui::Visuals::dark());
        let settings = cc
            .storage
            .and_then(|s| eframe::get_value(s, "settings"))
            .unwrap_or_default();
        let mut app = Self {
            settings,
            backend: None,
            adapters: Vec::new(),
            state: State::default(),
            error: None,
            tab: 0,
            replay: String::new(),
            fights: Vec::new(),
            fight: None,
            fight_skills: Vec::new(),
            history_player: None,
            pets: Value::Null,
            pet_names: serde_json::from_str(include_str!("../../overlay/data/pets.json"))
                .unwrap_or_default(),
            cube: None,
            click_through: false,
            hotkey_ok: false,
            hotkey: backend::hotkey(cc.egui_ctx.clone()),
        };
        app.apply_window(&cc.egui_ctx);
        app.refresh_adapters();
        if app.error.is_none() {
            app.start(&cc.egui_ctx);
        }
        app
    }

    fn apply_window(&self, ctx: &egui::Context) {
        ctx.send_viewport_cmd(ViewportCommand::WindowLevel(
            if self.settings.always_on_top {
                WindowLevel::AlwaysOnTop
            } else {
                WindowLevel::Normal
            },
        ));
        ctx.send_viewport_cmd(ViewportCommand::MousePassthrough(self.click_through));
    }

    fn refresh_adapters(&mut self) {
        match backend::adapters() {
            Ok(adapters) => {
                self.adapters = adapters;
                self.error = None;
            }
            Err(e) => self.error = Some(e),
        }
    }

    fn start(&mut self, ctx: &egui::Context) {
        self.backend.take();
        self.state = State::default();
        self.cube = None;
        match Backend::start(&self.settings.iface, &self.replay, ctx.clone()) {
            Ok(mut backend) => {
                backend.send(json!({"cmd":"history", "limit":100}));
                self.backend = Some(backend);
                self.error = None;
            }
            Err(e) => self.error = Some(e),
        }
    }

    fn send(&mut self, command: Value) {
        if let Some(backend) = &mut self.backend {
            backend.send(command);
        }
    }

    fn message(&mut self, value: Value) {
        match value["type"].as_str() {
            Some("state") => {
                if let Ok(state) = serde_json::from_value::<State>(value) {
                    self.state = state;
                }
            }
            Some("history") => {
                if let Ok(fights) = serde_json::from_value(value["fights"].clone()) {
                    self.fights = fights;
                }
            }
            Some("fight") => {
                if let Some((fight, skills)) = read_fight(&value) {
                    self.fight = Some(fight);
                    self.fight_skills = skills;
                }
                self.history_player = self
                    .fight
                    .as_ref()
                    .and_then(|f| f.players.first().map(|p| p.id));
            }
            Some("fightSaved") => self.send(json!({"cmd":"history", "limit":100})),
            Some("pets") => self.pets = value,
            Some("cube") => {
                self.cube = match value["event"].as_str() {
                    Some("near" | "distance") => Some(format!(
                        "Hidden cube nearby: {} m",
                        value["distance"]
                            .as_f64()
                            .map(|d| format!("{d:.0}"))
                            .unwrap_or_else(|| "?".into())
                    )),
                    Some("opening") => Some("Someone is opening a hidden cube".into()),
                    Some("opened" | "left") => None,
                    _ => self.cube.take(),
                };
            }
            _ => {}
        }
    }

    fn controls(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal_wrapped(|ui| {
            ui.heading("AION 2 Meter");
            if ui
                .checkbox(&mut self.settings.always_on_top, "Always on top")
                .changed()
            {
                self.apply_window(ctx);
            }
            if ui.checkbox(&mut self.settings.compact, "Compact").changed() {
                ctx.send_viewport_cmd(ViewportCommand::InnerSize(if self.settings.compact {
                    egui::vec2(440.0, 360.0)
                } else {
                    egui::vec2(760.0, 620.0)
                }));
            }
        });
        ui.horizontal_wrapped(|ui| {
            if self.backend.is_some() {
                if ui.button("Stop capture").clicked() {
                    self.backend.take();
                    self.state = State::default();
                }
            } else if ui.button("Start capture").clicked() {
                self.start(ctx);
            }
            if ui
                .add_enabled(self.backend.is_some(), egui::Button::new("Save & reset"))
                .clicked()
            {
                self.send(json!({"cmd":"reset"}));
            }
            if ui
                .add_enabled(
                    self.hotkey_ok,
                    egui::Button::new("Click-through (Ctrl+Alt+M)"),
                )
                .clicked()
            {
                self.toggle_click_through(ctx);
            }
        });
        if !self.settings.compact {
            ui.horizontal(|ui| {
                for (index, label) in ["Live meter", "Fight history", "Pets", "Settings"]
                    .iter()
                    .enumerate()
                {
                    if ui.selectable_label(self.tab == index, *label).clicked() {
                        self.tab = index;
                        if index == 1 {
                            self.send(json!({"cmd":"history", "limit":100}));
                        }
                    }
                }
            });
        }
        ui.separator();
    }

    fn toggle_click_through(&mut self, ctx: &egui::Context) {
        if !self.hotkey_ok {
            return;
        }
        self.click_through = !self.click_through;
        if self.click_through {
            self.settings.always_on_top = true;
        }
        self.apply_window(ctx);
    }

    fn live(&mut self, ui: &mut egui::Ui) {
        let status = if self.backend.is_none() && !self.replay.is_empty() && self.error.is_none() {
            "Replay finished"
        } else if self.backend.is_none() {
            "Capture stopped"
        } else if self.state.capture.locked {
            "Capturing game traffic"
        } else if self.state.capture.game_running {
            "Finding game traffic - enter combat"
        } else {
            "Waiting for AION2.exe"
        };
        ui.horizontal_wrapped(|ui| {
            ui.colored_label(
                if self.state.capture.locked {
                    Color32::LIGHT_GREEN
                } else {
                    Color32::YELLOW
                },
                status,
            );
            if let Some(ping) = self.state.ping_ms {
                ui.label(format!("{ping} ms"));
            }
            ui.label(format!(
                "{:.1} s",
                self.state.battle_time_ms as f64 / 1000.0
            ));
        });
        if let Some(target) = &self.state.target {
            ui.strong(&target.name);
            if target.max_hp > 0 && target.current_hp >= 0 {
                ui.add(
                    egui::ProgressBar::new(
                        (target.current_hp as f64 / target.max_hp as f64).clamp(0.0, 1.0) as f32,
                    )
                    .text(format!(
                        "{} / {} HP",
                        number(target.current_hp as f64),
                        number(target.max_hp as f64)
                    )),
                );
            }
        }
        if let Some(cube) = &self.cube {
            ui.colored_label(Color32::GOLD, cube);
        }
        if self.click_through {
            ui.colored_label(
                Color32::GOLD,
                "Click-through enabled. Ctrl+Alt+M to unlock.",
            );
        }
        if !self.settings.compact {
            ui.horizontal(|ui| {
                ui.label("Target:");
                for (value, label) in [
                    ("bossTargets", "Boss"),
                    ("allTargets", "All damage"),
                    ("lastHitByMe", "My target"),
                ] {
                    if ui
                        .selectable_label(self.state.target_mode == value, label)
                        .clicked()
                    {
                        self.send(json!({"cmd":"targetMode", "mode":value}));
                    }
                }
                if ui.button("My skills").clicked() {
                    self.send(json!({"cmd":"focus", "id":null}));
                }
            });
        }
        ui.add_space(8.0);
        if let Some(id) = player_table(ui, &self.state.players, "live-players") {
            self.send(json!({"cmd":"focus", "id":id}));
        }
        if self.state.players.is_empty() {
            ui.label("Start the game and deal damage to populate the meter.");
        }
        if !self.settings.compact && !self.state.skills.is_empty() {
            ui.separator();
            ui.heading("Skills");
            skill_table(ui, &self.state.skills);
        }
    }

    fn history(&mut self, ui: &mut egui::Ui) {
        ui.label("Saved boss fights (most recent 100). Select a fight, then a player for skills.");
        egui::ComboBox::from_id_salt("fight-picker")
            .selected_text(
                self.fight
                    .as_ref()
                    .map(|f| f.boss_name.as_str())
                    .unwrap_or("Choose a fight"),
            )
            .show_ui(ui, |ui| {
                let mut selected = None;
                for fight in &self.fights {
                    if ui
                        .selectable_label(
                            self.fight.as_ref().is_some_and(|f| f.id == fight.id),
                            format!(
                                "{} | {:.0}s | {} | {}",
                                fight.boss_name,
                                fight.duration_ms as f64 / 1000.0,
                                if fight.killed { "Killed" } else { "Attempt" },
                                fight.id
                            ),
                        )
                        .clicked()
                    {
                        selected = Some(fight.id.clone());
                    }
                }
                if let Some(id) = selected {
                    self.send(json!({"cmd":"fight", "id":id}));
                }
            });
        if let Some(fight) = &self.fight {
            ui.heading(&fight.boss_name);
            if let Some(id) = player_table(ui, &fight.players, "history-players") {
                self.history_player = Some(id);
            }
            let skills: Vec<_> = self
                .fight_skills
                .iter()
                .filter(|s| Some(s.actor_id) == self.history_player)
                .cloned()
                .collect();
            skill_table(ui, &skills);
        }
    }

    fn pets(&self, ui: &mut egui::Ui) {
        ui.heading("Pet collection");
        ui.label("Levels update at login and Kibelisk teleports. Teleport once if capture started after login.");
        if self.pets.is_null() {
            ui.label("Waiting for pet data.");
            return;
        }
        ui.label(format!("Server: {}", self.pets["server"]));
        egui::Grid::new("pets")
            .striped(true)
            .min_col_width(90.0)
            .show(ui, |ui| {
                for label in ["Pet", "Genus", "Level", "Soul points"] {
                    ui.strong(label);
                }
                ui.end_row();
                if let Some(pets) = self.pet_names["pets"].as_object() {
                    for (id, pet) in pets {
                        if pet["unreleased"].as_bool() == Some(true) {
                            continue;
                        }
                        let level = self.pets["levels"][id].as_u64().unwrap_or(0);
                        let points = self.pets["points"][id].as_u64().unwrap_or(0);
                        ui.label(pet["name"].as_str().unwrap_or(id));
                        ui.label(pet["genus"].as_str().unwrap_or(""));
                        ui.label(level.to_string());
                        ui.label(points.to_string());
                        ui.end_row();
                    }
                }
            });
    }

    fn settings(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.heading("Capture adapter");
        ui.label("Auto uses the default IPv4 route. For a VPN or multiple adapters, choose the interface carrying the game's traffic and restart capture.");
        egui::ComboBox::from_id_salt("adapter")
            .selected_text(
                self.adapters
                    .iter()
                    .find(|a| a.name == self.settings.iface)
                    .and_then(|a| a.description.as_deref())
                    .unwrap_or(if self.settings.iface.is_empty() {
                        "Auto (default route)"
                    } else {
                        &self.settings.iface
                    }),
            )
            .show_ui(ui, |ui| {
                ui.selectable_value(
                    &mut self.settings.iface,
                    String::new(),
                    "Auto (default route)",
                );
                for adapter in &self.adapters {
                    ui.selectable_value(
                        &mut self.settings.iface,
                        adapter.name.clone(),
                        format!(
                            "{} [{}]",
                            adapter.description.as_deref().unwrap_or(&adapter.name),
                            adapter.addresses.join(", ")
                        ),
                    );
                }
            });
        ui.horizontal(|ui| {
            if ui.button("Refresh adapters").clicked() {
                self.refresh_adapters();
            }
            if ui.button("Apply & restart capture").clicked() {
                self.start(ctx);
            }
        });
        ui.separator();
        ui.heading("Replay a capture");
        ui.label("Optional .pcap path. Clear this to return to live capture.");
        ui.text_edit_singleline(&mut self.replay);
        if ui.button("Start replay / live capture").clicked() {
            self.start(ctx);
        }
        ui.separator();
        ui.hyperlink_to(
            "Npcap download and installation",
            "https://npcap.com/#download",
        );
        ui.label("Install Npcap with 'WinPcap API-compatible Mode' enabled. Npcap is installed separately.");
        ui.label(format!(
            "Fights, pet data and capture.log: {}",
            backend::data_dir().display()
        ));
        ui.label("Use borderless/windowed game mode for Always on top. Ctrl+Alt+M toggles click-through. Closing this window saves the current fight and stops capture.");
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        #[cfg(feature = "ui-smoke")]
        if let Some(path) = std::env::var_os("AION2_METER_SCREENSHOT") {
            let captured = ctx.input(|i| {
                i.events.iter().find_map(|event| match event {
                    egui::Event::Screenshot { image, .. } => Some(image.clone()),
                    _ => None,
                })
            });
            if let Some(captured) = captured {
                let pixels: Vec<u8> = captured.pixels.iter().flat_map(|p| p.to_array()).collect();
                image::save_buffer(
                    path,
                    &pixels,
                    captured.width() as u32,
                    captured.height() as u32,
                    image::ColorType::Rgba8,
                )
                .expect("Save UI screenshot");
                ctx.send_viewport_cmd(ViewportCommand::Close);
            } else {
                ctx.send_viewport_cmd(ViewportCommand::Screenshot(Default::default()));
            }
        }
        while let Ok(event) = self.hotkey.try_recv() {
            match event {
                backend::Hotkey::Ready => self.hotkey_ok = true,
                backend::Hotkey::Toggle => self.toggle_click_through(ctx),
                backend::Hotkey::Error(e) => {
                    self.hotkey_ok = false;
                    self.click_through = false;
                    self.apply_window(ctx);
                    self.error = Some(e);
                }
            }
        }
        for _ in 0..256 {
            let message = self
                .backend
                .as_ref()
                .and_then(|b| b.messages.try_recv().ok());
            let Some(message) = message else { break };
            self.message(message);
        }
        if let Some(result) = self.backend.as_mut().and_then(Backend::exited) {
            self.backend.take();
            if let Err(error) = result {
                self.error = Some(error);
            }
        }
        #[cfg(feature = "ui-smoke")]
        {
            if let Ok(tab) = std::env::var("AION2_METER_SMOKE_TAB") {
                self.tab = tab.parse().unwrap_or(0);
            }
            if let Some(path) = std::env::var_os("AION2_METER_SMOKE_STATE") {
                self.state = serde_json::from_slice(&std::fs::read(path).expect("Read UI fixture"))
                    .expect("Parse UI fixture");
            }
        }
        egui::CentralPanel::default().show(ctx, |ui| {
            self.controls(ui, ctx);
            if let Some(error) = &self.error {
                ui.colored_label(Color32::LIGHT_RED, error);
            }
            if let Some(error) = &self.state.capture.error {
                ui.colored_label(Color32::LIGHT_RED, error);
            }
            egui::ScrollArea::vertical().show(ui, |ui| {
                match if self.settings.compact { 0 } else { self.tab } {
                    1 => self.history(ui),
                    2 => self.pets(ui),
                    3 => self.settings(ui, ctx),
                    _ => self.live(ui),
                }
            });
        });
        ctx.request_repaint_after(Duration::from_millis(200));
    }

    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        eframe::set_value(storage, "settings", &self.settings);
    }
}

fn player_table(ui: &mut egui::Ui, players: &[Player], id: &str) -> Option<i32> {
    let mut selected = None;
    egui::Grid::new(id)
        .striped(true)
        .min_col_width(52.0)
        .show(ui, |ui| {
            for label in ["Player", "DPS", "Damage", "Share", "Crit"] {
                ui.strong(label);
            }
            ui.end_row();
            for player in players {
                let name = RichText::new(&player.name).color(if player.is_local {
                    Color32::LIGHT_GREEN
                } else {
                    Color32::WHITE
                });
                if ui
                    .selectable_label(false, name)
                    .on_hover_text(&player.job)
                    .clicked()
                {
                    selected = Some(player.id);
                }
                ui.label(number(player.dps));
                ui.label(number(player.damage));
                ui.label(format!("{:.1}%", player.share));
                ui.label(format!("{:.1}%", player.crit_rate * 100.0));
                ui.end_row();
            }
        });
    selected
}

fn skill_table(ui: &mut egui::Ui, skills: &[Skill]) {
    egui::Grid::new("skills")
        .striped(true)
        .min_col_width(52.0)
        .show(ui, |ui| {
            for label in ["Skill", "Damage", "DPS", "Hits", "Crit", "Back"] {
                ui.strong(label);
            }
            ui.end_row();
            for skill in skills {
                ui.label(&skill.name);
                ui.label(number(skill.damage));
                ui.label(number(skill.dps));
                ui.label(skill.hits.to_string());
                ui.label(format!("{:.1}%", skill.crit_rate * 100.0));
                ui.label(format!("{:.1}%", skill.back_rate * 100.0));
                ui.end_row();
            }
        });
}
