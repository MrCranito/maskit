#!/bin/bash
# Carte pré-rendue de la Station Orbitale (pont 0 en croix) : export du plan → scène Blender →
# paquet du jeu → mini-carte. Reprenable : relancer la même commande ne refait que les morceaux
# manquants (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/ss_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=6]
#   ex. : tools/prerender/ss_pipeline.sh 948725 /tmp/ss948725
# Aperçu rapide : ss_pipeline.sh <seed> <work_dir> 12 4   (≈ 1 min ; ne pas livrer : le jeu et les
# tests exigent ≥ 72 px/case).
# Réglages du rendu (variables d'environnement, voir tools/prerender/ss_scene.py) : SS_EXPOSURE,
# SS_SUN, SS_LIGHT, SS_SKY, SS_SAT, SS_CON, SS_LIFT, SS_BLOOM, SS_EARTH (x,y,rayon en cases),
# SS_EARTH_L (direction de la lumière sur la Terre), SS_PLANET, SS_TILT.
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-6}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/space_station/$SEED"
mkdir -p "$WORK"
cd "$ROOT"
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_02_space_station.tres
python3 tools/prerender/ss_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,full,occ,int "$MARGIN"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/space_station/$SEED/"
godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
