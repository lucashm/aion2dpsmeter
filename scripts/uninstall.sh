#!/usr/bin/env bash
# Removes everything install.sh put in place. Your saved fights and overlay
# settings are kept unless you pass --purge.
set -uo pipefail

share="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
units=(aion2-meterd aion2-meter-overlay aion2-meter-tray)

systemctl --user disable --now "${units[@]}" 2>/dev/null
for u in "${units[@]}"; do rm -f "$config/systemd/user/$u.service"; done
systemctl --user daemon-reload

rm -f "$HOME/.local/bin/aion2-meterd" "$HOME/.local/bin/aion2-meter-tray" "$HOME/.local/bin/aion2-meter"
rm -rf "$config/quickshell/aion2-meter" "$share/aion2-meter/data"
rm -f "$share/applications/aion2-meter.desktop" "$share/icons/hicolor/scalable/apps/aion2-meter.svg"
update-desktop-database "$share/applications" 2>/dev/null

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$share/aion2-meter" "$config/aion2-meter"
    echo "Removed, including saved fights and settings."
else
    echo "Removed. Saved fights ($share/aion2-meter/fights) and settings ($config/aion2-meter) were kept; use --purge to delete them too."
fi
