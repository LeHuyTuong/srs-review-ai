#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIAGRAM_DIR="$SCRIPT_DIR"
RENDER_DIR="$DIAGRAM_DIR/rendered"
PLANTUML_JAR="${PLANTUML_JAR:-$HOME/.local/share/plantuml/plantuml.jar}"
MMD_CONFIG="${MMD_CONFIG:-}"

mkdir -p "$RENDER_DIR"

render_mermaid() {
  local src="$1"
  local base
  base="$(basename "$src" .mmd)"
  local svg="$RENDER_DIR/$base.svg"
  local png="$RENDER_DIR/$base.png"
  local -a cmd=(mmdc -i "$src" -o "$svg" -b white)
  if [[ -n "$MMD_CONFIG" ]]; then
    cmd+=( -p "$MMD_CONFIG" )
  fi
  "${cmd[@]}"
  mmdc -i "$src" -o "$png" -b white ${MMD_CONFIG:+-p "$MMD_CONFIG"}
  if grep -aEqi 'syntax error|cannot find graphviz|version[^<]{0,40}old|error:' "$svg" "$png" 2>/dev/null; then
    echo "Render verification failed for $src" >&2
    return 1
  fi
  echo "rendered: $svg"
  echo "rendered: $png"
}

render_plantuml() {
  local src="$1"
  local base
  base="$(basename "$src" .puml)"
  local svg="$RENDER_DIR/$base.svg"
  local png="$RENDER_DIR/$base.png"
  java -jar "$PLANTUML_JAR" -charset UTF-8 -Playout=smetana -tsvg -pipe < "$src" > "$svg"
  java -jar "$PLANTUML_JAR" -charset UTF-8 -Playout=smetana -tpng -pipe < "$src" > "$png"
  if grep -aEqi 'syntax error|cannot find graphviz|version[^<]{0,40}old|error:' "$svg" "$png" 2>/dev/null; then
    echo "Render verification failed for $src" >&2
    return 1
  fi
  echo "rendered: $svg"
  echo "rendered: $png"
}

if [[ $# -eq 0 ]]; then
  shopt -s nullglob
  sources=( "$DIAGRAM_DIR"/*.mmd "$DIAGRAM_DIR"/*.puml )
  if [[ ${#sources[@]} -eq 0 ]]; then
    echo "No .mmd or .puml files found in $DIAGRAM_DIR" >&2
    exit 1
  fi
elif [[ -d "$1" ]]; then
  shopt -s nullglob
  sources=( "$1"/*.mmd "$1"/*.puml )
else
  sources=( "$@" )
fi

for src in "${sources[@]}"; do
  [[ -f "$src" ]] || { echo "Missing source: $src" >&2; exit 1; }
  case "$src" in
    *.mmd) render_mermaid "$src" ;;
    *.puml) render_plantuml "$src" ;;
    *) echo "Unsupported diagram source: $src" >&2; exit 1 ;;
  esac
done
