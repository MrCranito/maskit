#!/bin/bash
# Carte pré-rendue du Carnaval hanté (parc d'attractions maudit, rez-de-chaussée) : export du plan →
# scène Blender → paquet du jeu → mini-carte. Reprenable : relancer la même commande ne refait que
# les morceaux manquants (dossier <work>/_chunks_full, b<id>_in.png déjà rendus conservés).
#
# Usage : tools/prerender/hc_pipeline.sh <seed> <work_dir> [ppc=72] [samples=16] [margin=6]
#   ex. : flock "${BLENDER_LOCK:-/home/claude/.blender_render.lock}" tools/prerender/hc_pipeline.sh 2025 /tmp/hc2025
# Aperçu rapide : hc_pipeline.sh <seed> <work_dir> 12 4   (≈ 2 min ; ne pas livrer : le jeu et les
# tests exigent ≥ 72 px/case).
# Réglages du rendu (variables d'environnement, voir tools/prerender/hc_scene.py) : HC_EXPOSURE,
# HC_MOON, HC_SKY, HC_LIGHT, HC_SAT, HC_CON, HC_LIFT, HC_BLOOM, HC_TILT.
# Verrous (docs/cartes2/CONTRAT.md) : les commandes godot passent par /home/claude/.godot.lock ;
# lancer ce script lui-même sous /home/claude/.blender_render.lock.
set -e
SEED=${1:?seed}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
MARGIN=${5:-6}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="$ROOT/assets/prerender/haunted_carnival/$SEED"
GLOCK=${GODOT_LOCK:-/home/claude/.godot.lock}
mkdir -p "$WORK"
cd "$ROOT"
flock "$GLOCK" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GLOCK" godot --headless --path . --script res://tools/prerender/export_layout.gd -- "$SEED" "$WORK/layout_in.json" "" \
	res://data/worlds/world_04_haunted_carnival.tres
python3 tools/prerender/hc_scene.py "$WORK/layout_in.json" "$WORK" "$PPC" "$SAMPLES" mask,full,occ,gnd,int "$MARGIN"
# Post-étalonnage (lueurs au sol, brume, forêt) : repart toujours du rendu brut qui vient d'être fait.
rm -f "$WORK"/*_raw.png
python3 tools/prerender/hc_grade.py "$WORK"
python3 tools/prerender/compose.py "$WORK" "$PACK" 1024 82
flock "$GLOCK" godot --headless --path . --import > /dev/null 2>&1 || true
flock "$GLOCK" godot --headless --path . --script tools/make_minimap.gd -- "res://assets/prerender/haunted_carnival/$SEED/"
flock "$GLOCK" godot --headless --path . --import > /dev/null 2>&1 || true
echo "Paquet : $PACK"
