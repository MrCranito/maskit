# Banc de profilage (perf/fluidite)

Un vrai raid joué par le bot de playtest (`tools/playtest/playtest_bot.gd`), **avec rendu**, et un
enregistreur de temps d'image (`perf_recorder.gd`). Seed fixe, `--fixed-fps 60` sans limite d'images :
le jeu avance de 1/60 s par image aussi vite que la machine le permet, donc 1800 images = 30 s de jeu.
Le temps de chaque image mesure son coût réel (logique + rendu).

```bash
godot --path . --fixed-fps 60 --resolution 2000x923 -s res://tools/perf_bench/perf_bench_main.gd -- \
  --map=perm_dust_creek --seed=42 --profile=agressif --difficulty=2 --frames=1800 --fire --out=bench.json
# Autres cartes : perm_station_kagami, perm_carnaval_hante, perm_terres_gelees, perm_pyramides_egypte
# --disable=FogOfWar,AmbientLights : nœuds de ces classes désactivés et cachés (coût d'un sous-système)
# --mark (avec --verbose de Godot) : marqueur « PB_F n » à chaque image, pour retrouver dans le journal
#   les ressources chargées pendant une image lente (« Loading resource: … »)
```

Isoler la sauvegarde : `override.cfg` (jamais commité) avec
`[application] config/use_custom_user_dir=true` et `config/custom_user_dir_name="RaidersGo_bench"`.

## Mesures (JSON)
`frame_ms` (moyenne, p50, p95, p99, pire), `process_ms` et `physics_ms` (chronos internes : du premier au
dernier nœud de l'image), `render_cpu_ms` / `render_gpu_ms` (RenderingServer), `draw_calls`, `nodes`,
`frames_over_16ms` / `25ms` / `33ms` / `50ms`, `nodes_added_per_s` et `nodes_added_top` (création de
nœuds, pooling absent), `objects_delta`, `static_mem_delta_mb`, `texture_mem_mb`, `spikes` (images lentes :
temps, process, physique, rendu, mémoire texture ajoutée, nœuds créés pendant l'image) et
`series_frame_ms` (toutes les images).

## Limites
- Mesure **relative** : comparer avant / après sur la même machine, au même moment, et répéter (2 passes
  au moins). La machine de dev est souvent chargée par d'autres travaux.
- Le GPU d'un PC ne reproduit pas le coût d'un GPU mobile à tuiles (copies de l'écran, remplissage à la
  résolution native) : ce qui en dépend se mesure sur le téléphone, avec l'overlay de fluidité
  (`scripts/debug/perf_overlay.gd`, F5 ou appui à trois doigts, versions de test).
- Le bot n'est pas déterministe d'une version à l'autre (IA, hasard des combats) : les pics isolés se
  comparent par leur cause, pas image par image.
