#!/usr/bin/env bash
# Lanzador de AssettoServer (Linux) con cambio de mapa independiente de los presets.
# Requiere: jq. Ejecutalo desde la carpeta de AssettoServer.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
EXE="$ROOT/AssettoServer"
SEL="$ROOT/map_selection.json"
FLAG="$ROOT/map_restart.flag"

apply_selection() {
  [ -f "$SEL" ] || return 0
  local track layout
  track="$(jq -r '.track' "$SEL")"
  layout="$(jq -r '.layout' "$SEL")"
  local files=()
  [ -f "$ROOT/cfg/server_cfg.ini" ] && files+=("$ROOT/cfg/server_cfg.ini")
  for f in "$ROOT"/presets/*/server_cfg.ini; do [ -f "$f" ] && files+=("$f"); done
  for f in "${files[@]}"; do
    sed -i -E "s/^TRACK=.*/TRACK=${track}/; s/^CONFIG_TRACK=.*/CONFIG_TRACK=${layout}/" "$f"
  done
  echo "[launcher] Mapa aplicado: ${track} / '${layout}' en ${#files[@]} ficheros"
  tmp="$(mktemp)"; jq '.restartRequested=false' "$SEL" > "$tmp" && mv "$tmp" "$SEL"
}

while true; do
  apply_selection
  rm -f "$FLAG"
  "$EXE" &
  PID=$!
  RESTART=0
  while kill -0 "$PID" 2>/dev/null; do
    if [ -f "$FLAG" ]; then   # modo RestartMode: File
      echo "[launcher] Reinicio solicitado (flag)"
      kill "$PID"; RESTART=1; break
    fi
    sleep 1
  done
  wait "$PID" 2>/dev/null
  if [ "$RESTART" -eq 0 ] && [ -f "$SEL" ] && [ "$(jq -r '.restartRequested' "$SEL")" = "true" ]; then RESTART=1; fi
  [ "$RESTART" -eq 1 ] || { echo "[launcher] El servidor se ha detenido."; break; }
  echo "[launcher] Reiniciando con el nuevo mapa..."; sleep 2
done
