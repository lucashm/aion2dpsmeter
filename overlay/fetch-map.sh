#!/usr/bin/env bash
# Downloads what the app's pet map draws, from Arkive (github.com/arkive-games/arkive,
# by tc-imba; its data is CC BY-NC 4.0): Verteron's, Altgard's and the Abyss's pet
# spawn markers and zone outlines with their English names, the pets' portraits,
# and the map tiles below full size (the app loads full-size tiles as you zoom in).
#   fetch-map.sh [dir]   (default: $XDG_DATA_HOME/aion2-meter/map)
# Does nothing when Arkive's data hasn't changed since the last run.
set -euo pipefail

DATA=https://data-aion2.tc-imba.com
RES=https://resource-aion2.tc-imba.com
dir=${1:-${XDG_DATA_HOME:-$HOME/.local/share}/aion2-meter/map}
# The maps: Verteron, Altgard (8x8 tiles, 3 sizes) and Chaotic Lower Reshanta (4x4, 2 sizes).
maps=(World_L_A World_D_A Abyss_Reshanta_A)
declare -A tiles=([World_L_A]=8 [World_D_A]=8 [Abyss_Reshanta_A]=4) levels=([World_L_A]=2 [World_D_A]=2 [Abyss_Reshanta_A]=1)

fetch() { curl -fsSL --retry 2 -A aion2dpsmeter "$@"; }

# Arkive's data version and this script's maps: either changing fetches again.
version="$(fetch "$DATA/version.json") ${maps[*]}"
if [ -f "$dir/version.json" ] && [ "$(cat "$dir/version.json")" = "$version" ]; then
    exit 0
fi

# Lines of "<url> <file>", fetched 8 at a time; files already here are kept.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
for m in "${maps[@]}"; do
    echo "$DATA/markers/$m.json $dir/markers/$m.json" >>"$list"
    echo "$DATA/locales/en-US/markers/$m.json $dir/names/$m.json" >>"$list"
    echo "$DATA/regions/$m.json $dir/regions/$m.json" >>"$list"
    echo "$DATA/locales/en-US/regions/$m.json $dir/region-names/$m.json" >>"$list"
done
# Markers first: the portraits are listed in them.
xargs -P 8 -n 2 sh -c 'mkdir -p "$(dirname "$2")" && curl -fsSL --retry 2 -A aion2dpsmeter -o "$2.part" "$1" && mv "$2.part" "$2"' _ <"$list"

: >"$list"
for m in "${maps[@]}"; do
    for level in $(seq "${levels[$m]}" -1 1); do
        n=$((${tiles[$m]} >> level))
        for x in $(seq 0 $((n - 1))); do
            for y in $(seq 0 $((n - 1))); do
                f=$(printf 'UI/Map/WorldMap/%s/Res/z-%d/%s_%02d_%02d.webp' "$m" "$level" "$m" "$x" "$y")
                [ -f "$dir/$f" ] || echo "$RES/$f $dir/$f" >>"$list"
            done
        done
    done
done
grep -oh '"icon": *"UI/Resource/Texture/Portrait/Portrait_Vehicle/[^"]*"' "$dir"/markers/*.json \
    | sed 's/.*"\(UI[^"]*\)"/\1/' | sort -u | while read -r f; do
    [ -f "$dir/$f" ] || echo "$RES/$f $dir/$f" >>"$list"
done
xargs -P 8 -n 2 sh -c 'mkdir -p "$(dirname "$2")" && curl -fsSL --retry 2 -A aion2dpsmeter -o "$2.part" "$1" && mv "$2.part" "$2"' _ <"$list"

printf '%s' "$version" >"$dir/version.json"
