#!/bin/sh
# Builds static x86_64 binaries (musl, libpcap linked in) and packs a release
# tarball into dist/. Runs on Alpine, as the release workflow does. Locally:
#   docker run --rm -v "$PWD":/src -w /src -e OWNER="$(id -u):$(id -g)" rust:alpine sh scripts/package.sh v0.1.0
set -eu

version="${1:?usage: package.sh vX.Y.Z}"

apk add --no-cache musl-dev libpcap-dev pkgconf file >/dev/null
# Link libpcap statically: its file name differs between distributions.
export PKG_CONFIG_ALL_STATIC=1
cargo build --release --locked --target-dir target/musl -p aion2-meterd -p aion2-meter-tray

for b in aion2-meterd aion2-meter-tray; do
    file "target/musl/release/$b" | grep -q "static" || { echo "$b is not statically linked" >&2; exit 1; }
done

name="aion2-meter-$version-x86_64-linux"
out="dist/$name"
rm -rf "$out"
mkdir -p "$out/bin" "$out/data/i18n"
cp target/musl/release/aion2-meterd target/musl/release/aion2-meter-tray scripts/aion2-meter "$out/bin/"
src=third_party/a2tools/src/data
cp -r "$src/i18n/skills" "$src/i18n/npcs" "$out/data/i18n/"
cp "$src/dot_skill_ids.json" "$src/skill_icons.json" "$src/abnormals.json" "$out/data/"
cp -r overlay systemd desktop "$out/"
cp scripts/install.sh scripts/uninstall.sh LICENSE README.md CHANGELOG.md "$out/"

tar -C dist -czf "dist/$name.tar.gz" "$name"
(cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
if [ -n "${OWNER:-}" ]; then chown -R "$OWNER" dist target/musl; fi
echo "dist/$name.tar.gz"
