#!/usr/bin/env bash
# Test d'intégration du coop en ligne, entièrement local :
#   1. lance le serveur relais (server/, Node.js) sur 127.0.0.1 ;
#   2. lance deux instances Godot headless (hôte + invité, profils isolés) qui passent par le
#      vrai salon puis le vrai raid (tools/net_smoke/smoke_client.gd) ;
#   3. renvoie 0 si les deux instances ont réussi toutes leurs vérifications.
# Options (variables d'environnement) :
#   NET_SMOKE_PORT  port du relais (défaut 18787)
#   NET_SMOKE_SHOTS dossier de captures : fenêtres réelles sous xvfb au lieu du mode headless
#   NET_SMOKE_KEEP  1 = garder le dossier temporaire (journaux)
#   NET_SMOKE_SERVER cloudflare = relais Cloudflare (server/cloudflare) sous `wrangler dev` au
#                   lieu du serveur Node (même protocole ; npm ci fait dans server/cloudflare)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${NET_SMOKE_PORT:-18787}"
TMP="$(mktemp -d -t raidersgo_net_XXXXXX)"
GODOT="${GODOT:-godot}"
SHOTS="${NET_SMOKE_SHOTS:-}"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  [ -n "${HOST_PID:-}" ] && kill "$HOST_PID" 2>/dev/null
  [ -n "${GUEST_PID:-}" ] && kill "$GUEST_PID" 2>/dev/null
  if [ "${NET_SMOKE_KEEP:-0}" != "1" ]; then rm -rf "$TMP"; else echo "Journaux : $TMP"; fi
}
trap cleanup EXIT

# --- Serveur relais ---------------------------------------------------------------------
WAIT_STEPS=50
if [ "${NET_SMOKE_SERVER:-node}" = "cloudflare" ]; then
  if [ ! -d "$ROOT/server/cloudflare/node_modules/wrangler" ]; then
    (cd "$ROOT/server/cloudflare" && npm ci --no-audit --no-fund >/dev/null 2>&1) || { echo "npm ci (cloudflare) a échoué"; exit 2; }
  fi
  (cd "$ROOT/server/cloudflare" && WRANGLER_SEND_METRICS=false node node_modules/wrangler/bin/wrangler.js dev \
    --port "$PORT" --ip 127.0.0.1 --var LOG:1 --show-interactive-dev-session=false) >"$TMP/server.log" 2>&1 &
  SERVER_PID=$!
  WAIT_STEPS=1200
else
  if [ ! -d "$ROOT/server/node_modules/ws" ]; then
    (cd "$ROOT/server" && npm ci --no-audit --no-fund >/dev/null 2>&1) || { echo "npm ci a échoué"; exit 2; }
  fi
  PORT="$PORT" LOG=1 node "$ROOT/server/index.js" >"$TMP/server.log" 2>&1 &
  SERVER_PID=$!
fi
for _ in $(seq 1 "$WAIT_STEPS"); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 0.1
done
if ! curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "Relais injoignable sur le port $PORT"; cat "$TMP/server.log"; exit 2
fi

# --- Deux clients Godot -----------------------------------------------------------------
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1
run_client() {
  local role="$1" extra=()
  mkdir -p "$TMP/$role"
  if [ -n "$SHOTS" ]; then
    local x=0; [ "$role" = "guest" ] && x=1290
    extra=(--rendering-driver opengl3 --audio-driver Dummy --position "$x,0" --resolution 1280x720 --windowed)
    XDG_DATA_HOME="$TMP/$role" xvfb-run -a -s "-screen 0 1300x760x24" \
      "$GODOT" "${extra[@]}" --path "$ROOT" -s res://tools/net_smoke/smoke_client.gd -- \
      --role="$role" --url="ws://127.0.0.1:$PORT" --dir="$TMP" --shots="$SHOTS" >"$TMP/$role.log" 2>&1
  else
    XDG_DATA_HOME="$TMP/$role" "$GODOT" --headless --path "$ROOT" -s res://tools/net_smoke/smoke_client.gd -- \
      --role="$role" --url="ws://127.0.0.1:$PORT" --dir="$TMP" >"$TMP/$role.log" 2>&1
  fi
}
export RAIDERSGO_NET_URL="ws://127.0.0.1:$PORT"
run_client host &
HOST_PID=$!
sleep 1
run_client guest &
GUEST_PID=$!
wait "$HOST_PID"; HOST_RC=$?
wait "$GUEST_PID"; GUEST_RC=$?
HOST_PID=""; GUEST_PID=""

echo "--- hôte (code $HOST_RC) ---"
grep -E "OK |ÉCHEC|TERMINÉ|SCRIPT ERROR" "$TMP/host.log" | head -60
echo "--- invité (code $GUEST_RC) ---"
grep -E "OK |ÉCHEC|TERMINÉ|SCRIPT ERROR" "$TMP/guest.log" | head -60
if [ "$HOST_RC" -eq 0 ] && [ "$GUEST_RC" -eq 0 ]; then
  echo "NET SMOKE TEST : SUCCÈS"
  exit 0
fi
echo "NET SMOKE TEST : ÉCHEC"
echo "--- fin du journal hôte ---"; tail -25 "$TMP/host.log"
echo "--- fin du journal invité ---"; tail -25 "$TMP/guest.log"
exit 1
