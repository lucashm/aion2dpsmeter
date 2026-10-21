#!/usr/bin/env bash
# Rebuilds the release tarball from the working tree (needs docker), then
# reinstalls from it the way a user would: its uninstall.sh, then its
# install.sh. The installed daemon is set aside during the uninstall so it
# keeps its capture permission, and install.sh keeps it when it's unchanged,
# so sudo is only asked for when the daemon changed.
set -euo pipefail

cd "$(dirname "$0")/.."
version="v$(sed -n 's/^version = "\(.*\)"/\1/p' daemon/Cargo.toml)"
# package.sh prints only the tarball path on stdout.
tarball="$(docker run --rm -v "$PWD":/src -w /src -e OWNER="$(id -u):$(id -g)" rust:alpine sh scripts/package.sh "$version" | tail -1)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xzf "$tarball" -C "$work"
pkg="$(echo "$work"/aion2-meter-*/)"

bin="$HOME/.local/bin/aion2-meterd"
# A rename keeps the file's capabilities; a copy wouldn't.
if [[ -f "$bin" ]]; then mv "$bin" "$bin.keep"; fi
"$pkg/uninstall.sh"
if [[ -f "$bin.keep" ]]; then mv "$bin.keep" "$bin"; fi
"$pkg/install.sh"
