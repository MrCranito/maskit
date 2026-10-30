#!/bin/bash
# Carte pré-rendue des Terres gelées (surface) : export du plan → scène Blender → paquet du jeu →
# mini-carte. Reprenable : relancer la même commande ne refait que les morceaux manquants
# (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/fl_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=6]
#   ex. : flock "${BLENDER_LOCK:-/home/claude/.blender_render.lock}" tools/prerender/fl_pipeline.sh 12345 /tmp/fl12345
# Aperçu rapide : fl_pipeline.sh <seed> <work_dir> 12 4   (≈ 2 min ; ne pas livrer : le jeu et les
# tests exigent ≥ 72 px/case).
# Réglages du rendu (variables d'environnement, voir tools/prerender/fl_scene.py) : FL_EXPOSURE,
# FL_SUN, FL_SKY, FL_ICELIGHT, FL_LIGHT, FL_SAT, FL_CON, FL_LIFT, FL_BLOOM, FL_TILT.
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-6}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/frozen_lands/$SEED"
mkdir -p "$WORK"
cd "$ROOT"
flock "${GODOT_LOCK:-/home/claude/.godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
flock "${GODOT_LOCK:-/home/claude/.godot.lock}" godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_05_frozen_lands.tres
flock "${BLENDER_LOCK:-/home/claude/.blender_render.lock}" python3 tools/prerender/fl_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,full,occ,int "$MARGIN"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
flock "${GODOT_LOCK:-/home/claude/.godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
flock "${GODOT_LOCK:-/home/claude/.godot.lock}" godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/frozen_lands/$SEED/"
flock "${GODOT_LOCK:-/home/claude/.godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
