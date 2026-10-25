#!/bin/bash
# Pull test-walk logs off the phone and summarize them.
#
#   tools/pull-logs.sh [device-id]
#
# Wireless transfers drop the socket fairly often, hence the retries. Copying
# files one at a time is far more reliable than copying the directory.
set -uo pipefail

# Grab the UUID by pattern, not by column: device names contain spaces
# ("iPhone (3)"), which shifts every positional field.
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null \
  | grep -E 'available|connected' \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | head -1)}"
# Set BUNDLE=<bundle id> for a build with a different bundle ID.
BUNDLE="${BUNDLE:-com.sathvik.homestep}"
OUT="logs"

[ -z "$DEVICE" ] && { echo "No device found. Plug in or connect over Wi-Fi."; exit 1; }
mkdir -p "$OUT"
echo "device: $DEVICE"

FILES=$(xcrun devicectl device info files --device "$DEVICE" \
          --domain-type appDataContainer --domain-identifier "$BUNDLE" --username mobile 2>/dev/null \
        | awk '{print $1}' | grep '^Documents/sessions/.*\.jsonl$')

[ -z "$FILES" ] && { echo "No session logs on the device yet — tap Start and walk."; exit 0; }

for f in $FILES; do
    name=$(basename "$f")
    [ -s "$OUT/$name" ] && { echo "have  $name"; continue; }
    for attempt in 1 2 3; do
        xcrun devicectl device copy from --device "$DEVICE" \
            --domain-type appDataContainer --domain-identifier "$BUNDLE" --user mobile \
            --source "$f" --destination "$OUT/$name" >/dev/null 2>&1
        [ -s "$OUT/$name" ] && { echo "got   $name ($(wc -l < "$OUT/$name" | tr -d ' ') rows)"; break; }
        echo "retry $name ($attempt)"
    done
done

echo
for f in "$OUT"/*.jsonl; do
    [ -s "$f" ] && python3 tools/analyze-log.py "$f"
done
