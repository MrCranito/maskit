#!/bin/bash
# Carte pré-rendue des Pyramides d'Égypte (surface : complexe de temples) : export du plan → scène Blender →
# paquet du jeu → mini-carte. Reprenable : relancer la même commande ne refait que les morceaux
# manquants (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/eg_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=6]
#   ex. : tools/prerender/eg_pipeline.sh 2026 /tmp/eg2026
# Aperçu rapide : eg_pipeline.sh <seed> <work_dir> 12 4   (≈ 1 min ; ne pas livrer : le jeu et les
# tests exigent ≥ 72 px/case).
# Verrous (2 cœurs partagés) : Blender via flock /home/claude/.blender_render.lock, Godot via
# flock /home/claude/.godot.lock. Réglages (variables d'environnement, voir eg_scene.py) :
# EG_EXPOSURE, EG_SUN, EG_SKY, EG_LIGHT, EG_SAT, EG_CON, EG_LIFT, EG_BLOOM, EG_TILT.
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-6}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/egypt_pyramids/$SEED"
GL=${GODOT_LOCK:-/home/claude/.godot.lock}
BL=${BLENDER_LOCK:-/home/claude/.blender_render.lock}
mkdir -p "$WORK"
cd "$ROOT"
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GL" godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_06_egypt_pyramids.tres
# Rendu reprenable par tranches (SLICE_S secondes, défaut 720) : le verrou Blender est rendu entre
# deux tranches aux autres agents ; les morceaux déjà rendus (_chunks_full) sont conservés.
SLICE=${SLICE_S:-720}
flock "$BL" timeout 3000 python3 tools/prerender/eg_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,occ "$MARGIN"
until grep -q "^FULL" "$WORK/full.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/eg_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" full "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/full.log" || true
	sleep 2
done
until grep -q "^INT" "$WORK/int.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/eg_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" int "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/int.log" || true
	sleep 2
done
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GL" godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/egypt_pyramids/$SEED/"
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
