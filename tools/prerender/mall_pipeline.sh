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
# MALL_CON, MALL_LIFT, MALL_BLOOM, MALL_TILT.
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
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_03_mall.tres
python3 tools/prerender/mall_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,full,occ,gnd,int "$MARGIN"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/mall/$SEED/"
godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
