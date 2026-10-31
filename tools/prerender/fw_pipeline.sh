#!/bin/bash
# Carte pré-rendue du Far West (Dust Creek, étage 0) : export du plan → scène Blender → étalonnage
# → paquet du jeu → mini-carte. Reprenable : relancer la même commande ne refait que les morceaux
# manquants (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/fw_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=4]
#   ex. : source tools/prerender/mac_env.sh && tools/prerender/fw_pipeline.sh 642439 /tmp/fw642439
# Aperçu rapide : fw_pipeline.sh <seed> <work_dir> 12 4   (ne pas livrer : le jeu et les tests
# exigent ≥ 72 px/case).
# Le paquet doit correspondre au plan du générateur (map.json tiles_md5) : le générateur commun
# (scripts/dungeon/*) n'est pas modifié par le rendu.
# Verrous (agents parallèles) : Blender via flock $BLENDER_LOCK, Godot via flock $GODOT_LOCK.
# Réglages (variables d'environnement, voir fw_scene.py / fw_grade.py) : FW_EXPOSURE, FW_SUN,
# FW_SKY, FW_SAT, FW_CON, FW_LIFT, FW_TILT, FW_GRADE_*.
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-4}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/far_west/$SEED"
GL=${GODOT_LOCK:-/tmp/maskit_godot.lock}
BL=${BLENDER_LOCK:-/tmp/maskit_blender.lock}
mkdir -p "$WORK"
cd "$ROOT"
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GL" godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_01_far_west.tres
# Rendu reprenable par tranches (SLICE_S secondes, défaut 720) : le verrou Blender est rendu entre
# deux tranches aux autres agents ; les morceaux déjà rendus (_chunks_full) sont conservés.
SLICE=${SLICE_S:-720}
flock "$BL" timeout 3000 python3 tools/prerender/fw_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,occ "$MARGIN"
until grep -q "^FULL" "$WORK/full.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/fw_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" full "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/full.log" || true
	sleep 2
done
until grep -q "^INT" "$WORK/int.log" 2>/dev/null; do
	flock "$BL" timeout "$SLICE" python3 tools/prerender/fw_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" int "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/int.log" || true
	sleep 2
done
# Passe « sol seul » (ground_pass.py, après occ, avant l'étalonnage) : g<id>.png + grounds.json,
# reprenable (g<id>.png déjà rendus conservés). render.json est sauvegardé puis restauré : une
# passe isolée le réécrirait sans la liste des bâtiments.
until grep -q "^GND" "$WORK/gnd.log" 2>/dev/null; do
	[ -f "$WORK/render.json" ] && cp "$WORK/render.json" "$WORK/render.json.keep"
	flock "$BL" timeout "$SLICE" python3 tools/prerender/fw_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" gnd "$MARGIN" \
		2>&1 | grep -v "Saved\|Fra:\|Deprecation\|use_nodes" | tee "$WORK/gnd.log" || true
	[ -f "$WORK/render.json.keep" ] && mv "$WORK/render.json.keep" "$WORK/render.json"
	sleep 2
done
python3 tools/prerender/fw_grade.py "$WORK"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GL" godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/far_west/$SEED/"
flock "$GL" godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
