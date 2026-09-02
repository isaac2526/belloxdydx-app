#!/usr/bin/env bash
# ============================================================
# Build the app for web, serve it, and drive it through a real
# browser against the mock backend. Screenshots and a pass/fail
# report land in build/uitest/.
#
#   ./tools/test_app.sh            # full run
#   ./tools/test_app.sh --no-build # reuse the last web build
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER="${FLUTTER:-/opt/flutter/bin/flutter}"
export PUB_CACHE="${PUB_CACHE:-/opt/pubcache}"
MOCK_PORT=54321
WEB_PORT=8080
OUT="$ROOT/build/uitest"

mkdir -p "$OUT"

cleanup() {
  [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null
  [[ -n "${WEB_PID:-}"  ]] && kill "$WEB_PID"  2>/dev/null
}
trap cleanup EXIT

# A stale server from a previous run would keep the port, silently serve
# the old fixtures, and swallow this run's log. `ss` cannot see listeners
# without privileges in some containers, so match on the command line —
# both patterns are specific enough not to match this script.
pkill -9 -f "tools/mock_backend.js" 2>/dev/null || true
pkill -9 -f "bx-static-file-server" 2>/dev/null || true
sleep 1

echo "==> starting mock backend on :$MOCK_PORT"
node tools/mock_backend.js "$MOCK_PORT" >"$OUT/mock.log" 2>&1 &
MOCK_PID=$!
sleep 1.5
curl -sf -X POST "http://127.0.0.1:$MOCK_PORT/rest/v1/rpc/bx_capabilities" \
  -H 'Content-Type: application/json' -d '{}' >/dev/null \
  || { echo "FATAL: mock backend did not start"; cat "$OUT/mock.log"; exit 1; }

if [[ "${1:-}" != "--no-build" ]]; then
  echo "==> building for web"
  "$FLUTTER" build web --release --no-web-resources-cdn \
    --dart-define=BX_SUPABASE_URL="http://127.0.0.1:$MOCK_PORT" \
    --dart-define=BX_SUPABASE_ANON_KEY=mock-anon-key \
    --dart-define=BX_SITE_URL="http://127.0.0.1:$MOCK_PORT" \
    2>&1 | tail -20
  [[ -f build/web/index.html ]] || { echo "web build failed"; exit 1; }
fi

echo "==> serving build/web on :$WEB_PORT"
node -e "
/* bx-static-file-server */
const http=require('http'),fs=require('fs'),p=require('path');
const root=p.join(process.cwd(),'build','web');
const mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript',
'.json':'application/json','.wasm':'application/wasm','.css':'text/css',
'.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml',
'.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2','.bin':'application/octet-stream',
'.symbols':'application/octet-stream','.map':'application/json'};
http.createServer((req,res)=>{
  let f=decodeURIComponent(req.url.split('?')[0]);
  if(f==='/')f='/index.html';
  let full=p.join(root,f);
  if(!fs.existsSync(full)||fs.statSync(full).isDirectory())full=p.join(root,'index.html');
  res.setHeader('Cross-Origin-Opener-Policy','same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy','credentialless');
  res.writeHead(200,{'Content-Type':mime[p.extname(full)]||'application/octet-stream'});
  fs.createReadStream(full).pipe(res);
}).listen($WEB_PORT,'127.0.0.1',()=>console.log('serving'));
" >"$OUT/web.log" 2>&1 &
WEB_PID=$!
sleep 1.5

echo "==> driving the app"
node tools/drive_app.js "http://127.0.0.1:$WEB_PORT" "$OUT"
STATUS=$?

echo
echo "==> artefacts in $OUT"
ls "$OUT"/*.png 2>/dev/null | wc -l | xargs echo "screenshots:"
exit $STATUS
