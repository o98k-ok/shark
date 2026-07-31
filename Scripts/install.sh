#!/bin/bash
# Builds the bundle and installs it into /Applications, replacing any previous copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
DESTINATION="${SHARK_INSTALL_DIR:-/Applications}"
INSTALLED="$DESTINATION/Shark.app"

"$ROOT/Scripts/build-app.sh" "$CONFIGURATION"

if [ ! -w "$DESTINATION" ]; then
    echo "Cannot write to $DESTINATION (needs an admin account)." >&2
    exit 1
fi

# Overwriting the bundle of a live process leaves it half-swapped, so stop it first.
if pgrep -f "$INSTALLED/Contents/MacOS/Shark" >/dev/null; then
    echo "Quitting the running copy"
    pkill -f "$INSTALLED/Contents/MacOS/Shark"
    for _ in $(seq 30); do
        pgrep -f "$INSTALLED/Contents/MacOS/Shark" >/dev/null || break
        sleep 0.1
    done
fi

rm -rf "$INSTALLED"
cp -R "$ROOT/dist/Shark.app" "$INSTALLED"

echo "Installed $INSTALLED"
open "$INSTALLED"
