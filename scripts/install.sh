#!/usr/bin/env bash
# Builds and installs the meter for the current user:
#   ~/.local/bin/aion2-meterd            the capture daemon (gets cap_net_raw via sudo setcap)
#   ~/.local/share/aion2-meter/data      skill/NPC names from A2Tools
#   ~/.config/quickshell/aion2-meter     -> this repo's overlay/ (edits apply live)
#   ~/.config/systemd/user/aion2-meter*.service
# Re-run after `git pull` / `git submodule update`: a rebuild drops the capability.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="$HOME/.local/bin"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/aion2-meter/data"
qs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

step() { printf '\n\033[1;33m==>\033[0m %s\n' "$*"; }

step "Checking dependencies"
missing=()
command -v cargo >/dev/null || missing+=(rust)
command -v qs >/dev/null || missing+=(quickshell)
command -v setcap >/dev/null || missing+=(libcap)
pkg-config --exists libpcap 2>/dev/null || [[ -e /usr/lib/libpcap.so ]] || missing+=(libpcap)
if ((${#missing[@]})); then
    echo "Missing: ${missing[*]}  (on CachyOS/Arch: sudo pacman -S --needed ${missing[*]})"
    exit 1
fi

step "Fetching the A2Tools parser (submodule)"
git -C "$repo" submodule update --init --recursive

step "Building the daemon and tray"
cargo build --release --manifest-path "$repo/Cargo.toml" -p aion2-meterd -p aion2-meter-tray

step "Installing the daemon to $bin_dir"
install -Dm700 "$repo/target/release/aion2-meterd" "$bin_dir/aion2-meterd"

step "Granting packet-capture permission (sudo setcap)"
echo "Only this one binary gets cap_net_raw/cap_net_admin; the overlay runs unprivileged."
sudo setcap cap_net_raw,cap_net_admin=eip "$bin_dir/aion2-meterd"
getcap "$bin_dir/aion2-meterd"

step "Installing game data to $data_dir"
src="$repo/third_party/a2tools/src/data"
mkdir -p "$data_dir/i18n"
rm -rf "$data_dir/i18n/skills" "$data_dir/i18n/npcs"
cp -r "$src/i18n/skills" "$src/i18n/npcs" "$data_dir/i18n/"
cp "$src/dot_skill_ids.json" "$src/abnormals.json" "$data_dir/"

step "Linking the overlay into $qs_dir/aion2-meter"
mkdir -p "$qs_dir" "${XDG_CONFIG_HOME:-$HOME/.config}/aion2-meter"
ln -sfn "$repo/overlay" "$qs_dir/aion2-meter"

step "Installing the launcher (aion2-meter command, app menu entry)"
install -Dm755 "$repo/scripts/aion2-meter" "$bin_dir/aion2-meter"
install -Dm755 "$repo/target/release/aion2-meter-tray" "$bin_dir/aion2-meter-tray"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$apps"
# Launchers may not have ~/.local/bin on PATH: use the full path.
sed "s|Exec=aion2-meter|Exec=$bin_dir/aion2-meter|" "$repo/desktop/aion2-meter.desktop" > "$apps/aion2-meter.desktop"
install -Dm644 "$repo/desktop/aion2-meter.svg" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/aion2-meter.svg"
update-desktop-database "$apps" 2>/dev/null || true

step "Installing systemd user units"
mkdir -p "$unit_dir"
install -m644 "$repo/systemd/aion2-meterd.service" "$repo/systemd/aion2-meter-overlay.service" "$repo/systemd/aion2-meter-tray.service" "$unit_dir/"
systemctl --user daemon-reload

cat <<'EOF'

Done. Start/stop from the app menu ("AION 2 Meter") or with: aion2-meter [toggle|start|stop|status]
To start both now and at every login:

    systemctl --user enable --now aion2-meterd aion2-meter-overlay
    systemctl --user enable --now aion2-meter-tray      # tray icon with the controls

Then add keybinds to ~/.config/hypr/config/binds.lua (pick any free keys):

    hl.bind("SUPER + SHIFT + D", hl.dsp.global("aion2meter:edit"))         -- move widgets / settings
    hl.bind("SUPER + SHIFT + H", hl.dsp.global("aion2meter:history"))      -- fight history
    hl.bind("SUPER + SHIFT + R", hl.dsp.global("aion2meter:reset"))        -- save + reset meter
    hl.bind("SUPER + SHIFT + O", hl.dsp.global("aion2meter:toggle"))       -- hide/show widgets
    hl.bind("SUPER + SHIFT + K", hl.dsp.global("aion2meter:next-player"))  -- cycle skill breakdown

Logs: journalctl --user -u aion2-meterd -f
EOF
