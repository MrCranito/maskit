# Trois nouvelles cartes (branche `feature/cartes-carnaval-glace-egypte`)

Planche de référence : `docs/reference/cartes_2.png` (1606×979). Trois colonnes, de gauche à droite :

| Colonne | Carte | Biome (id) | Monde | Légende de la planche |
|---|---|---|---|---|
| gauche (x 0‑535) | **Carnaval hanté** — ancien parc d'attractions maudit, de nuit, néons violets/roses, rires dans le vent, manèges brisés | `haunted_carnival` (préfixe `hc_`) | `data/worlds/world_04_haunted_carnival.tres` | Attractions, Roulottes, Manèges, Salle du boss |
| milieu (x 535‑1070) | **Les Terres gelées** — continent prisonnier des glaces, bases abandonnées, laboratoires enfouis, tempêtes perpétuelles | `frozen_lands` (préfixe `fl_`) | `data/worlds/world_05_frozen_lands.tres` | Bases militaires, Bunkers, Laboratoires, Salle du boss |
| droite (x 1070‑1606) | **Les Pyramides d'Égypte** — désert, pyramides millénaires, tombes, pièges, trésors oubliés | `egypt_pyramids` (préfixe `eg_`) | `data/worlds/world_06_egypt_pyramids.tres` | Pyramides, Temples, Trésors, Salle du boss |

Même démarche que pour Dust Creek (Far West), la Station Kagami et les Galeries Lumière :
**générateur → `export_layout.gd` → scène Blender pré‑rendue (passes full / int / mask / occ) →
`compose.py` → paquet `assets/prerender/<biome>/<seed>/` → mini‑carte → carte jouable**, avec une
visée ≥ 70 % de similitude avec la colonne de la planche (et ses 4 vignettes du bas).

## Organisation
- 1 agent par carte, tous dans la même copie `/home/claude/maskit`, branche
  `feature/cartes-carnaval-glace-egypte`. **Les agents ne font ni commit ni push** : le chef de
  projet committe et ouvre la PR.
- Machine : **2 cœurs CPU pour 3 agents.** Tout rendu Blender passe par
  `flock /home/claude/.blender_render.lock <commande>` ; toute commande Godot (import, test, export)
  par `flock /home/claude/.godot.lock godot --headless ...`. Codez pendant que les autres rendent ;
  itérez en basse résolution (ppc 12, samples 4), rendu final reprenable à 72 px/case.
- Captures : `/tmp/claude-0/-home-claude/e0bdc8a1-40bd-55ff-aaa7-e9333f948c56/scratchpad/shots/<carnival|frozen|egypt>/`
  (`compare_N.png` côte à côte avec la colonne de la planche, `M_overview.png`,
  `M_ingame_1..3.png`).

## Fichiers : qui possède quoi
| Zone | Propriétaire |
|---|---|
| `scripts/biomes/haunted_carnival/*`, `tools/prerender/hc_*`, `assets/prerender/haunted_carnival/**`, `assets/sprites/haunted_carnival/**`, `art/blender/haunted_carnival/*`, `data/worlds/world_04_haunted_carnival.tres`, `data/maps/perm_carnaval_hante.tres`, `assets/ui/maps/haunted_carnival.png`, `tests/test_haunted_carnival.gd`, `docs/cartes2/haunted_carnival.md`, section `[haunted_carnival]` de balance.cfg | agent Carnaval |
| idem avec `frozen_lands` / `fl_` / `world_05_frozen_lands.tres` / `perm_terres_gelees.tres` / `[frozen_lands]` | agent Terres gelées |
| idem avec `egypt_pyramids` / `eg_` / `world_06_egypt_pyramids.tres` / `perm_pyramides_egypte.tres` / `[egypt_pyramids]` | agent Pyramides |
| `scripts/biomes/biome_registry.gd` (une entrée biome + un builder, ajout d'une ligne), `tools/prerender/export_layout.gd` et `scripts/dungeon/prerender_backdrop.gd` (ajouts génériques seulement), `data/balance.cfg` clé `[maps] only_ids` (ajout de son id), `assets/ui/maps/build_map_thumbs.py` (ajout de sa vignette) | partagés : édition **minimale et additive avec Edit**, relire la ligne juste avant, noter le changement dans `docs/cartes2/<biome>.md` |
| tout le reste | chef de projet |

## Contrat technique (identique aux biomes existants, voir `docs/CONVENTIONS.md` § Biomes)
- `WorldData` complet : `generator_path`, `builder_path`, `containers_dir`, `floor_names`,
  `enemy_roster`, `container_kinds`, `prop_kinds`, `palette`, `music_explore/combat`.
- Générateur `static func generate_run(seed, world, difficulty) -> Array[FloorLayout]` :
  déterministe, connectivité garantie, salles super_loot verrouillées par clef, extraction,
  `hiding_spot_spawns`, perf < 50 ms/étage. Constructeur `static func build(layout, world) -> Node2D`
  avec l'API de `WorldBuilder` (`get_doors`, `get_stairs_areas`, `stairs_entered`,
  `get_room_at_world`, `set_stairs_cooldown`), murs couche world, `DoorNode`, z_index du contrat.
- **Ennemis : pas de nouveau monstre dans cette passe** (bestiaire = demande séparée). Le roster
  réutilise provisoirement des monstres existants : Carnaval → `mall_*`, Terres gelées → `ss_*`,
  Pyramides → `fw_*` (ids réels : voir `data/enemies/`). Pas de boss/élites nouveaux ; la « Salle du
  boss » de la légende est une salle `boss` du générateur avec le boss existant du monde emprunté.
- Conteneurs et cachettes du biome : sprites dans `containers_dir`, tables `data/loot_tables/`,
  objets `data/items/<prefixe>_*.tres`.
- Pré‑rendu : `tools/prerender/<prefixe>_scene.py` et `<prefixe>_pipeline.sh` sur le modèle de
  `mall_scene.py` / `mall_pipeline.sh` (même projection, mêmes passes, blocs génériques repris de
  `fw_scene.py`) ; paquet ≥ 72 px/case ; mini‑carte via `tools/make_minimap.gd` ; portes visibles
  depuis la caméra inclinée, collisions par emprise, occlusion des toits, tourelles sur murs
  visibles.
- `MapCard` `data/maps/perm_<carte>.tres` (permanent, `accent_color`, tags, vignette) + ajout de
  l'id à `[maps] only_ids` **seulement quand le rendu final 72 px/case est livré et vérifié**
  (l'APK Android se reconstruit à chaque push).
- Tests : `tests/test_<biome>.gd` (connectivité, déterminisme, perf, paquet pré‑rendu présent et
  ≥ 72 px/case, portes, extraction, super_loot) ; suite GUT complète verte (signaler les échecs des
  autres).
- Évaluation honnête à chaque itération (≥ 4) : `compare_N.png` + note sur 10 critères adaptés
  (volume/angle, plan général, éléments signature de la planche, intérieurs, extérieurs, palette,
  lumière, matières, lisibilité en jeu, vignettes).

## Phase 2 (après les cartes) : bestiaire propre à chaque monde
Planche : `docs/reference/bestiaire_cartes_2.png` (6 monstres communs, 2 élites, 1 boss par monde).
Même contrat que `docs/bestiaire/CONTRAT.md` (ids `hc_*`, `fl_*`, `eg_*`, planches 8 directions
sous Blender, EnemyData, compétences, roster, élites `elite_kinds`, boss 3 phases). Les rosters
provisoires (mall/ss/fw) seront remplacés par ces monstres.
