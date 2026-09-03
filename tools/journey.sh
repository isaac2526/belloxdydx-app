#!/usr/bin/env bash
# ============================================================
# Drives the REAL app through the REAL offline path.
#
# The web harness (tools/test_app.sh) cannot test any of this: on web
# there is no documents directory, so OfflineStore.open() returns null
# and the whole offline layer is skipped. This runs the app as a Linux
# desktop binary instead — a real filesystem, a real HTTP stack, real
# files on disk — against the same mock backend.
#
#   ./tools/journey.sh              # legacy path (what production runs)
#   ./tools/journey.sh --direct     # the Supabase RPC path
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER="${FLUTTER:-/opt/flutter/bin/flutter}"
PORT=54321
WORK="${BX_JOURNEY_DIR:-$ROOT/build/journey}"
LEGACY=true
[[ "${1:-}" == "--direct" ]] && LEGACY=false

rm -rf "$WORK"
mkdir -p "$WORK/home/Documents" "$WORK/home/config" "$WORK/bin"

# path_provider_linux shells out to xdg-user-dir to find the documents
# directory. Containers rarely ship it; the app is unchanged, this only
# gives the harness somewhere to write.
cat > "$WORK/bin/xdg-user-dir" <<SHIM
#!/bin/sh
echo "$WORK/home/Documents"
SHIM
chmod +x "$WORK/bin/xdg-user-dir"

cleanup() { [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null; }
trap cleanup EXIT

# A mock left over from an earlier run would keep the port AND its
# in-memory device register, so the run would hit the new-device
# challenge and look like a failure that is really a stale process.
# Matched through /proc rather than pkill, whose pattern would also
# match this script's own command line.
for pid in /proc/[0-9]*; do
  p="${pid#/proc/}"
  if tr '\0' ' ' < "$pid/cmdline" 2>/dev/null | grep -q "mock_backend.js $PORT"; then
    kill "$p" 2>/dev/null
  fi
done
sleep 1

# BX_PROD_SIM hides the bx_* RPCs, which is what makes the app fall back
# to the website API -- the shape production is actually in today. The
# --direct run leaves them exposed so the Supabase path is exercised.
echo "==> mock backend on :$PORT (prod-sim=$LEGACY)"
if [[ "$LEGACY" == "true" ]]; then
  BX_PROD_SIM=1 node tools/mock_backend.js "$PORT" > "$WORK/mock.log" 2>&1 &
else
  node tools/mock_backend.js "$PORT" > "$WORK/mock.log" 2>&1 &
fi
MOCK_PID=$!
sleep 2

export PATH="$WORK/bin:$PATH"
export XDG_DATA_HOME="$WORK/home"
export XDG_CONFIG_HOME="$WORK/home/config"
export XDG_CACHE_HOME="$WORK/home/cache"
export NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost"

echo "==> driving the app (legacy=$LEGACY)"
xvfb-run -a --server-args="-screen 0 1200x2400x24" \
  "$FLUTTER" test integration_test/offline_journey_test.dart -d linux \
  --dart-define=BX_SUPABASE_URL="http://127.0.0.1:$PORT" \
  --dart-define=BX_SUPABASE_ANON_KEY=mock-anon-key \
  --dart-define=BX_SITE_URL="http://127.0.0.1:$PORT" \
  --dart-define=BX_FORCE_LEGACY_API=$LEGACY \
  --dart-define=BX_MOCK_PID="$MOCK_PID" 2>&1 | tee "$WORK/run.log" \
  | grep -E "journey\]|overflowed|EXCEPTION|Expected|Actual|MUST|All tests|Some tests" \
  | cut -c1-400

echo
echo "==> what landed on the phone"
find "$WORK/home/Documents/offline" -type f 2>/dev/null \
  | sed "s|$WORK/home/Documents/offline/||" | sort | head -40
echo "    total: $(find "$WORK/home/Documents/offline" -type f 2>/dev/null | wc -l) files"

grep -q "All tests passed" "$WORK/run.log" && exit 0 || exit 1
