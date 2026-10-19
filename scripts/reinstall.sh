#!/usr/bin/env bash
# Reinstalls from the newest tarball in dist/ the way a user would: its
# uninstall.sh, then its install.sh. The installed daemon is set aside during
# the uninstall so it keeps its capture permission, and install.sh keeps it
# when it's unchanged, so sudo is only asked for when the daemon changed.
set -euo pipefail

tarball="$(ls -t "$(dirname "$0")"/../dist/aion2-meter-*.tar.gz | head -1)"
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
