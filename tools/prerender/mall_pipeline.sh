#!/bin/bash
# Carte pré-rendue des Galeries Lumière (centre commercial abandonné, rez-de-chaussée + parking) : export du plan → scène Blender →
# paquet du jeu → mini-carte. Reprenable : relancer la même commande ne refait que les morceaux
# manquants (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/mall_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=6]
#   ex. : tools/prerender/mall_pipeline.sh 2025 /tmp/mall2025
# Aperçu rapide : mall_pipeline.sh <seed> <work_dir> 12 4   (≈ 1 min ; ne pas livrer : le jeu et les
# tests exigent ≥ 72 px/case).
# Réglages du rendu (variables d'environnement, voir tools/prerender/mall_scene.py) : MALL_EXPOSURE,
# MALL_MOON, MALL_SKY, MALL_LIGHT, MALL_LIGHT_Z, MALL_LIGHT_SIZE, MALL_GAL_STEP, MALL_GAL_K, MALL_SAT,
# MALL_CON, MALL_LIFT, MALL_BLOOM, MALL_TILT, MALL_AO, MALL_WALL_T, MALL_H_SHOP… ; étalonnage :
# MALL_GRADE_* (tools/prerender/mall_grade.py).
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-6}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/mall/$SEED"
mkdir -p "$WORK"
cd "$ROOT"
flock "${GODOT_LOCK:-/tmp/maskit_godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
flock "${GODOT_LOCK:-/tmp/maskit_godot.lock}" godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_03_mall.tres
BL=${BLENDER_LOCK:-/tmp/maskit_blender.lock}
# Rendu reprenable par tranches (SLICE_S secondes, défaut 720) : le verrou Blender est rendu entre
# deux tranches aux autres agents ; les morceaux déjà rendus (_chunks_full, b<id>_in.png) sont gardés.
SLICE=${SLICE_S:-720}
flock "$BL" python3 tools/prerender/mall_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,occ "$MARGIN"
until grep -q "^FULL" "$WORK/full.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/mall_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" full "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/full.log" || true
	sleep 2
done
until grep -q "^INT" "$WORK/int.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/mall_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" int "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/int.log" || true
	sleep 2
done
# Passe « sol seul » (ground_pass.py, après occ, avant l'étalonnage) : g<id>.png + grounds.json,
# reprenable (g<id>.png déjà rendus conservés). render.json est sauvegardé puis restauré : une
# passe isolée le réécrirait sans la liste des bâtiments.
until grep -q "^GND" "$WORK/gnd.log" 2>/dev/null; do
	[ -f "$WORK/render.json" ] && cp "$WORK/render.json" "$WORK/render.json.keep"
	flock "$BL" timeout "$SLICE" python3 tools/prerender/mall_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" gnd "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/gnd.log" || true
	[ -f "$WORK/render.json.keep" ] && mv "$WORK/render.json.keep" "$WORK/render.json"
	sleep 2
done
# étalonnage calé sur la planche (originaux gardés en *_raw.png)
python3 tools/prerender/mall_grade.py "$WORK"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
flock "${GODOT_LOCK:-/tmp/maskit_godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
flock "${GODOT_LOCK:-/tmp/maskit_godot.lock}" godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/mall/$SEED/"
flock "${GODOT_LOCK:-/tmp/maskit_godot.lock}" godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
