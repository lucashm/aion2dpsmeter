#!/usr/bin/env bash
# Installs the meter for the current user, from a release download or from a
# source checkout (then it builds first):
#   ~/.local/bin/aion2-meterd            capture daemon (gets cap_net_raw via sudo setcap)
#   ~/.local/bin/aion2-meter-tray        tray icon
#   ~/.local/bin/aion2-meter             start/stop/edit command
#   ~/.local/share/aion2-meter/data      skill and NPC names (from A2Tools)
#   ~/.config/quickshell/aion2-meter     the overlay
#   ~/.config/systemd/user/aion2-meter*.service
# Run it again to update. Remove everything with uninstall.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
share="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"

step() { printf '\n\033[1;33m==>\033[0m %s\n' "$*"; }

# A release has bin/ next to this script; a checkout has it in scripts/.
if [[ -x "$here/bin/aion2-meterd" ]]; then
    root="$here"
    built="$root/bin"
    launcher="$root/bin/aion2-meter"
    data_src="$root/data"
else
    root="$(cd "$here/.." && pwd)"
    built="$root/target/release"
    launcher="$root/scripts/aion2-meter"
    data_src="$root/third_party/a2tools/src/data"
fi

step "Checking dependencies"
missing=()
command -v qs >/dev/null || missing+=(quickshell)
command -v setcap >/dev/null || missing+=(setcap)
if [[ "$built" == "$root/target/release" ]]; then
    command -v cargo >/dev/null || missing+=(rust)
    pkg-config --exists libpcap 2>/dev/null || missing+=(libpcap)
fi
if ((${#missing[@]})); then
    echo "Missing: ${missing[*]}. Install them with your package manager (see README) and run this again."
    exit 1
fi

if [[ "$built" == "$root/target/release" ]]; then
    step "Building from source"
    git -C "$root" submodule update --init --recursive
    cargo build --release --manifest-path "$root/Cargo.toml" -p aion2-meterd -p aion2-meter-tray
fi

step "Installing programs to $bin_dir"
# 700: a binary that can capture network traffic is for you only.
install -Dm700 "$built/aion2-meterd" "$bin_dir/aion2-meterd"
install -Dm755 "$built/aion2-meter-tray" "$bin_dir/aion2-meter-tray"
install -Dm755 "$launcher" "$bin_dir/aion2-meter"

step "Allowing the daemon to capture packets (sudo setcap)"
echo "Only aion2-meterd gets this permission; the overlay and tray run as you, unprivileged."
sudo setcap cap_net_raw,cap_net_admin=eip "$bin_dir/aion2-meterd"

step "Installing game data"
mkdir -p "$share/aion2-meter/data/i18n"
rm -rf "$share/aion2-meter/data/i18n/skills" "$share/aion2-meter/data/i18n/npcs"
cp -r "$data_src/i18n/skills" "$data_src/i18n/npcs" "$share/aion2-meter/data/i18n/"
cp "$data_src/dot_skill_ids.json" "$data_src/skill_icons.json" "$data_src/abnormals.json" "$share/aion2-meter/data/"

step "Installing the overlay"
mkdir -p "$config/quickshell" "$config/aion2-meter"
rm -rf "$config/quickshell/aion2-meter"
cp -r "$root/overlay" "$config/quickshell/aion2-meter"

step "Adding the app menu entry"
mkdir -p "$share/applications"
# One icon per faction; the tray switches to the last logged-in character's.
for f in elyos asmodian; do install -Dm644 "$root/desktop/aion2-meter-$f.png" "$share/aion2-meter/icons/$f.png"; done
faction="$(cat "$share/aion2-meter/faction" 2>/dev/null || true)"
[[ "$faction" == asmodian ]] || faction=elyos
# Full paths: launchers may not have ~/.local/bin on PATH, and an icon given
# by file can't be mixed up with an older one cached under the same name.
sed -e "s|Exec=aion2-meter|Exec=$bin_dir/aion2-meter|" -e "s|^Icon=.*|Icon=$share/aion2-meter/icons/$faction.png|" \
    "$root/desktop/aion2meter.desktop" > "$share/applications/aion2meter.desktop"
# Icons and the app menu entry from older versions.
rm -f "$share/icons/hicolor/scalable/apps/aion2-meter.svg" "$share/icons/hicolor/256x256/apps/aion2-meter.png" "$share/applications/aion2-meter.desktop"
update-desktop-database "$share/applications" 2>/dev/null || true

step "Starting the services (and at every login)"
units=(aion2-meterd aion2-meter-overlay aion2-meter-tray)
mkdir -p "$config/systemd/user"
for u in "${units[@]}"; do install -m644 "$root/systemd/$u.service" "$config/systemd/user/"; done
systemctl --user daemon-reload
systemctl --user enable "${units[@]}"
systemctl --user restart "${units[@]}"

cat <<'EOF'

Done. The meter is running, and a tray icon controls it.
Keybinds and everything else: see the README.
Logs: journalctl --user -u aion2-meterd -f
EOF
