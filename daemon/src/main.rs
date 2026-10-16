//! aion2-meterd: captures AION 2's traffic on Linux, runs it through A2Tools'
//! parser, and serves live combat state to the Quickshell overlay over a
//! Unix socket.

mod capture;
mod dispatch;
mod game;
mod history;
mod ipc;
mod meter;
mod tcp;

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use a2tools::combat::data_storage::DataStorage;
use a2tools::combat::dps_calculator::DpsCalculator;
use a2tools::combat::ping_tracker::PingTracker;
use a2tools::i18n::lookup::{self, NpcLookup, SkillLookup};
use anyhow::{Context, Result};
use parking_lot::Mutex;
use tracing::{error, info, warn};

use crate::dispatch::{CaptureStatus, Dispatcher};
use crate::history::History;
use crate::ipc::{Clients, Command};
use crate::meter::Meter;

const USAGE: &str = "\
aion2-meterd — AION 2 combat capture daemon

USAGE: aion2-meterd [OPTIONS]

  --iface NAME      capture interface (default: the one with the default route)
  --pcap FILE       replay a capture file instead of capturing live
  --realtime        with --pcap, replay at the original pace
  --record FILE     also save every captured frame to FILE (pcap), for bug reports
  --data DIR        A2Tools data directory (skill/NPC names)
  --lang CODE       language for skill and NPC names (en, de, fr, ko, ...; default en)
  --socket PATH     overlay socket (default: $XDG_RUNTIME_DIR/aion2-meter.sock)
  --print           print each state update to stdout (debugging)
";

struct Args {
    iface: Option<String>,
    pcap: Option<PathBuf>,
    realtime: bool,
    record: Option<PathBuf>,
    data: Option<PathBuf>,
    lang: String,
    socket: PathBuf,
    print: bool,
}

fn parse_args() -> Result<Args> {
    let mut a = Args {
        iface: None,
        pcap: None,
        realtime: false,
        record: None,
        data: None,
        lang: "en".into(),
        socket: ipc::default_socket_path(),
        print: false,
    };
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut value = || it.next().with_context(|| format!("{arg} needs a value"));
        match arg.as_str() {
            "--iface" => a.iface = Some(value()?),
            "--pcap" => a.pcap = Some(value()?.into()),
            "--realtime" => a.realtime = true,
            "--record" => a.record = Some(value()?.into()),
            "--data" => a.data = Some(value()?.into()),
            "--lang" => a.lang = value()?,
            "--socket" => a.socket = value()?.into(),
            "--print" => a.print = true,
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => anyhow::bail!("unknown option {other}\n\n{USAGE}"),
        }
    }
    Ok(a)
}

fn data_home() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share"))
        .join("aion2-meter")
}

/// Where A2Tools' data files are: given, installed, or the source checkout.
fn find_data_dir(given: Option<PathBuf>) -> Option<PathBuf> {
    let exe_dir = std::env::current_exe().ok().and_then(|p| p.parent().map(Path::to_path_buf));
    let mut candidates: Vec<PathBuf> = given.into_iter().collect();
    candidates.push(data_home().join("data"));
    candidates.push("/usr/share/aion2-meter/data".into());
    if let Some(d) = exe_dir {
        // target/{debug,release}/ -> repo root
        candidates.push(d.join("../../third_party/a2tools/src/data"));
    }
    candidates.push("third_party/a2tools/src/data".into());
    candidates.into_iter().find(|d| d.join("i18n/skills").is_dir())
}

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as i64
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,a2tools_dps_meter_lib=warn".into()),
        )
        .with_writer(std::io::stderr)
        .init();
    let args = parse_args()?;

    // ── parser core ────────────────────────────────────────────────────────
    let skills = SkillLookup::new();
    let npcs = NpcLookup::new();
    let storage = Arc::new(DataStorage::new());
    let mut dot_ids = HashSet::new();
    match find_data_dir(args.data.clone()) {
        Some(dir) => {
            info!("Game data: {}", dir.display());
            lookup::load_language(&skills, &npcs, &dir, &args.lang);
            if let Ok(text) = std::fs::read_to_string(dir.join("dot_skill_ids.json")) {
                dot_ids.extend(serde_json::from_str::<Vec<i32>>(&text).unwrap_or_default());
            }
            if let Ok(text) = std::fs::read_to_string(dir.join("abnormals.json")) {
                storage.set_abnormal_stack_limits(a2tools::capture::abnormal::stack_limits(&text));
            }
        }
        None => warn!("A2Tools data directory not found: skills and NPCs will show as numbers (see --data)"),
    }
    let skills = Arc::new(skills);
    let npcs = Arc::new(npcs);
    let ping = Arc::new(PingTracker::new());
    let calc = DpsCalculator::new(storage.clone(), skills.clone(), npcs.clone(), ping.clone());
    let meter = Arc::new(Mutex::new(Meter::new(calc, storage.clone(), ping.clone())));
    let history = Arc::new(History::new(data_home().join("fights"))?);
    let status = Arc::new(Mutex::new(CaptureStatus::default()));
    let clients = Clients::default();

    // Fights are saved before the game's zone changes clear them.
    {
        let (meter, history, clients, names) = (meter.clone(), history.clone(), clients.clone(), storage.clone());
        storage.set_before_reset(move || {
            let records = meter.lock().calc.snapshot_boss_fights_force();
            save_fights(&history, &clients, &names, records);
        });
    }

    // ── overlay socket ─────────────────────────────────────────────────────
    let (cmd_tx, cmd_rx) = mpsc::channel::<Command>();
    let force_send = Arc::new(std::sync::atomic::AtomicBool::new(true));
    {
        let force_send = force_send.clone();
        ipc::serve(&args.socket, clients.clone(), cmd_tx, move || {
            force_send.store(true, std::sync::atomic::Ordering::Relaxed);
        })?;
    }

    // ── capture ────────────────────────────────────────────────────────────
    let (seg_tx, seg_rx) = mpsc::sync_channel(16_384);
    let replay = args.pcap.is_some();
    let source = match &args.pcap {
        Some(path) => capture::Source::File { path: path.clone(), realtime: args.realtime },
        None => {
            let iface = args.iface.clone().or_else(capture::default_route_iface).unwrap_or_else(|| "any".into());
            capture::Source::Live { iface }
        }
    };
    {
        let status = status.clone();
        let record = args.record.clone();
        std::thread::Builder::new().name("capture".into()).spawn(move || {
            match capture::run(source, record, seg_tx) {
                Ok(()) => info!("Capture finished"),
                Err(e) => {
                    error!("Capture stopped: {e:#}");
                    status.lock().error = Some(format!("{e:#}"));
                }
            }
        })?;
    }

    // ── parse: segments -> streams -> A2Tools ──────────────────────────────
    let parse_done = Arc::new(std::sync::atomic::AtomicBool::new(false));
    {
        let status = status.clone();
        let parse_done = parse_done.clone();
        let mut dispatcher = Dispatcher::new(storage.clone(), skills, npcs, ping, dot_ids);
        dispatcher.replay = replay;
        std::thread::Builder::new().name("parse".into()).spawn(move || {
            let mut reasm = tcp::Reassembler::default();
            let mut chunks = Vec::new();
            // A replayed capture is the game's by definition.
            let mut game = if replay { game::GameState { pids: vec![0], local_ports: HashSet::new() } } else { game::scan() };
            dispatcher.on_game_state(&game);
            let mut last_scan = Instant::now();
            loop {
                let seg = match seg_rx.recv_timeout(Duration::from_millis(500)) {
                    Ok(seg) => Some(seg),
                    Err(mpsc::RecvTimeoutError::Timeout) => None,
                    Err(mpsc::RecvTimeoutError::Disconnected) if replay => break,
                    // Live capture failed: keep reporting the game's state
                    // (and the error) to the overlay.
                    Err(mpsc::RecvTimeoutError::Disconnected) => {
                        std::thread::sleep(Duration::from_millis(500));
                        None
                    }
                };
                if !replay && last_scan.elapsed() >= Duration::from_secs(2) {
                    game = game::scan();
                    dispatcher.on_game_state(&game);
                    last_scan = Instant::now();
                }
                if let Some(seg) = seg {
                    reasm.push(seg, &mut chunks);
                    for chunk in chunks.drain(..) {
                        // A connection the game opened since the last scan.
                        if !replay
                            && Dispatcher::is_foreign(&game, &chunk)
                            && last_scan.elapsed() >= Duration::from_millis(250)
                        {
                            game = game::scan();
                            dispatcher.on_game_state(&game);
                            last_scan = Instant::now();
                        }
                        dispatcher.on_chunk(&game, chunk);
                    }
                }
                dispatcher.tick(if replay { dispatcher.last_parsed_ms } else { now_ms() });
                let mut s = status.lock();
                let error = s.error.take();
                *s = dispatcher.status.clone();
                s.error = error;
            }
            parse_done.store(true, std::sync::atomic::Ordering::Relaxed);
        })?;
    }

    // ── meter: state to the overlay, fights to disk ────────────────────────
    let mut last_sent: Option<meter::OverlayState> = None;
    let mut last_save = Instant::now();
    loop {
        std::thread::sleep(Duration::from_millis(200));
        while let Ok(cmd) = cmd_rx.try_recv() {
            handle_command(cmd, &meter, &history, &clients, &storage);
            force_send.store(true, std::sync::atomic::Ordering::Relaxed);
        }
        let capture = status.lock().clone();
        let state = meter.lock().state(capture);
        let forced = force_send.swap(false, std::sync::atomic::Ordering::Relaxed);
        if forced || last_sent.as_ref() != Some(&state) {
            let line = serde_json::to_string(&state)?;
            if args.print {
                println!("{line}");
            }
            clients.broadcast(&line);
            last_sent = Some(state);
        }
        if last_save.elapsed() >= Duration::from_secs(5) {
            last_save = Instant::now();
            let records = meter.lock().calc.snapshot_boss_fights();
            save_fights(&history, &clients, &storage, records);
        }
        if replay && parse_done.load(std::sync::atomic::Ordering::Relaxed) {
            let records = meter.lock().calc.snapshot_boss_fights_force();
            save_fights(&history, &clients, &storage, records);
            info!("Replay finished");
            if args.print {
                let state = meter.lock().state(status.lock().clone());
                println!("{}", serde_json::to_string_pretty(&state)?);
            }
            return Ok(());
        }
    }
}

/// A2Tools masks every name but yours in a saved fight ("Ka****A"); put the
/// real names back from what the game told us, so history shows who it was.
fn unmask_names(record: &mut a2tools::entity::fight_record::FightRecord, storage: &DataStorage) {
    let names = storage.get_nicknames();
    let summons = storage.get_summon_data();
    for actor in &mut record.actors {
        let owner = a2tools::entity::summon_resolver::resolve(actor.actor_id, &summons);
        if let Some(name) = names.get(&actor.actor_id).or_else(|| names.get(&owner)).filter(|n| !n.is_empty()) {
            actor.nickname = name.clone();
        }
    }
}

fn save_fights(
    history: &History,
    clients: &Clients,
    storage: &DataStorage,
    records: Vec<a2tools::entity::fight_record::FightRecord>,
) {
    for mut record in records {
        unmask_names(&mut record, storage);
        match history.save(&record) {
            Ok(()) => {
                info!("Saved fight: {} ({})", record.boss_name, record.id);
                let msg = serde_json::json!({ "type": "fightSaved", "fight": history::summarize(&record) });
                clients.broadcast(&msg.to_string());
            }
            Err(e) => warn!("Could not save fight {}: {e:#}", record.id),
        }
    }
}

fn handle_command(cmd: Command, meter: &Mutex<Meter>, history: &History, clients: &Clients, storage: &DataStorage) {
    match cmd {
        Command::Reset => {
            let records = meter.lock().calc.snapshot_boss_fights_force();
            save_fights(history, clients, storage, records);
            meter.lock().calc.restart_target_selection(true);
            info!("Meter reset");
        }
        Command::TargetMode { mode } => meter.lock().calc.set_target_selection_mode(&mode),
        Command::Focus { id } => meter.lock().focus = id,
        Command::History { limit } => {
            let fights = history.list(limit.unwrap_or(30).min(200));
            clients.broadcast(&serde_json::json!({ "type": "history", "fights": fights }).to_string());
        }
        Command::Fight { id } => {
            let Some(record) = history.load(&id) else { return };
            let skills: Vec<_> = record
                .details
                .skills
                .iter()
                .map(|s| serde_json::json!({
                    "actorId": s.actor_id, "code": s.code, "name": s.name, "damage": s.dmg,
                    "hits": s.time, "crit": s.crit, "back": s.back, "isDot": s.is_dot,
                }))
                .collect();
            let msg = serde_json::json!({ "type": "fight", "summary": history::summarize(&record), "skills": skills });
            clients.broadcast(&msg.to_string());
        }
    }
}
