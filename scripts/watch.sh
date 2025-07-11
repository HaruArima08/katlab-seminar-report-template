#!/usr/bin/env bash
set -euo pipefail

cd /workspace || {
  echo "[ERROR] Cannot change directory to /workspace" >&2
  exit 1
}

tex_compile() {
  local tex="$1"
  echo "[INFO] Compiling: $tex"
  TEXINPUTS=./src//: LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 latexmk -pdfdvi "$tex"
  mkdir -p pdf
  cp "build/$(basename "$tex" .tex).pdf" pdf/ || echo "[WARN] Failed to copy PDF for $tex"
}

compile_all() {
  for tex in src/*.tex; do
    [ -f "$tex" ] && tex_compile "$tex"
  done
  echo "[INFO] Compilation finished. Watching for further changes..."
}

###############################
# 監視方式の自動選択
###############################
monitor_method="polling"
if command -v inotifywait >/dev/null 2>&1; then
  echo "[INFO] Testing inotifywait availability..."
  tmpfile=$(mktemp)
  inotifywait -q -e modify "$tmpfile" --timeout 1 >/dev/null 2>&1 &
  pid=$!
  sleep 0.3
  echo "x" >> "$tmpfile"
  if wait $pid 2>/dev/null; then
    monitor_method="inotify"
  fi
  rm -f "$tmpfile"
fi

echo "[INFO] Using $monitor_method based monitoring"

###############################
# inotify 監視
###############################
if [[ "$monitor_method" == "inotify" ]]; then
  while inotifywait -qq -r -e modify,create,delete,move src/; do
    echo "[INFO] Change detected via inotify"
    compile_all
  done
  exit 0
fi

###############################
# ポーリング監視 (全環境対応)
###############################
declare -A file_times
for tex in src/*.tex; do
  [[ -f "$tex" ]] && file_times["$tex"]=$(stat -c %Y "$tex" 2>/dev/null || stat -f %m "$tex")
  echo "[INFO] Tracking: $tex"
done

while true; do
  changed=false
  for tex in src/*.tex; do
    if [[ -f "$tex" ]]; then
      current=$(stat -c %Y "$tex" 2>/dev/null || stat -f %m "$tex")
      if [[ "${file_times[$tex]:-}" != "$current" ]]; then
        changed=true
        file_times["$tex"]=$current
        echo "[INFO] Change detected in: $tex"
      fi
    fi
  done
  if $changed; then
    compile_all
  fi
  sleep 2
done 
