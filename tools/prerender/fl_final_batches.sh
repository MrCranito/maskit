#!/bin/bash
# Rendu final fragmenté des Terres gelées : lots de FL_CHUNK_LIMIT morceaux (≈ 10 min de verrou
# Blender chacun), le verrou est rendu entre deux lots ; reprend jusqu'à ce que full/occ/int soient
# complets. Usage : tools/prerender/fl_final_batches.sh <layout.json> <work_dir> [ppc=72] [samples=16] [chunks_per_batch=8]
set -e
LAYOUT=${1:?layout.json}
WORK=${2:?work_dir}
PPC=${3:-72}
SAMPLES=${4:-16}
PER=${5:-8}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
for i in $(seq 1 40); do
	set +e
	FL_CHUNK_LIMIT=$PER flock /home/claude/.blender_render.lock python3 tools/prerender/fl_scene.py "$LAYOUT" "$WORK" "$PPC" "$SAMPLES" mask,full,occ,int 6 > "$WORK/batch_$i.log" 2>&1
	rc=$?
	set -e
	echo "batch $i rc=$rc $(grep -c chunk "$WORK/batch_$i.log") lines"
	if [ $rc -eq 0 ]; then
		echo "FINAL DONE"
		exit 0
	fi
	if [ $rc -ne 3 ]; then
		echo "batch failed (rc=$rc), see $WORK/batch_$i.log"
		exit $rc
	fi
	sleep 20
done
