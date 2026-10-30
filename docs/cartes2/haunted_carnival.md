# Carnaval hanté (`haunted_carnival`, préfixe `hc_`)

Planche : `docs/reference/cartes_2.png`, colonne de gauche (x 0‑535). Monde
`data/worlds/world_04_haunted_carnival.tres` (« Carnaval hanté »), carte `data/maps/perm_carnaval_hante.tres`
(`perm_carnaval_hante`, difficulté 2, nuit).

## Ce qui est fait
- **Plan** (`scripts/biomes/haunted_carnival/hc_plan.gd`) : parc portrait 72×126, un seul étage (0, pré-rendu).
  Allée centrale pavée du portail au nord, allées transversales en terre, place du chapiteau au centre,
  4 cours (grande roue NO, chaises volantes NE, tasses SO, carrousel SE), colonnes et rangées de stands
  (auvent rayé = toit qui s'efface, ou ouverts), **bâtiments en dur** (hangars, ateliers, musée des
  horreurs, galerie des jeux : murs de brique, moitié à toit) en bandes de part et d'autre de la place et
  dans les cours sud, 2 tentes rondes (palais des glaces / monstres / théâtre), 4 roulottes dont la
  **roulotte du Directeur** scellée (`super_loot`, clef `key_hc_director`), 4 kiosques, 2 sorties de
  secours (extraction) aux coins nord, **grand chapiteau ovale 32×24** = salle `boss` (anneau de gradins
  de 2 cases, 3 passages creusés dont l'entrée sud à escalier), portail à tête de clown au sud sur le
  parvis d'apparition, pylônes des montagnes russes dans la cour NE (obstacles), grande roue et manèges =
  disques murés (obstacles rendus en 3D). Contour **irrégulier** : morsures de forêt (`BITES`, cases de
  rue hors allées protégées rendues à la forêt, poches isolées comprises) puis palissade recalculée. Variations par seed : découpe / rôles / toits des
  stands, position des roulottes, rôle des tentes, Directeur. Contrat de rendu en métadonnée
  `render_contract` (modules, rides, coaster, tent, gate…).
- **Générateur** `hc_generator.gd` (`generate_run` / `generate_floor`, étage 0 seul), **peupleur**
  `hc_populator.gd` (décors `hc_*` par rôle, conteneurs, cachettes, ennemis `mall_*` provisoires, boss
  `mall_omnistore` dans la piste, gardes du Directeur), **réglages** `[haunted_carnival]` de balance.cfg.
- **Constructeur** `hc_builder.gd` (API WorldBuilder, collisions par cases fusionnées, portes `hc_door.gd` :
  rideau rayé / roulotte / grille / scellée, toits logiques `CarnivalRoof` — l'ovale du chapiteau est testé
  comme une ellipse —, repli 2D peint quand aucun paquet pré-rendu n'existe, `prerender_hide`).
- **Conteneurs / cachettes** (sprites Blender `art/blender/haunted_carnival/build_hc_props.py` →
  `assets/sprites/haunted_carnival/containers/`) : caisse de forain, comptoir de stand, coffre de roulotte,
  poubelle du parc, forain tombé, peluche éventrée ; cachettes photomaton, benne, tas de peluches, derrière le
  comptoir, sous la couchette. Tables `data/loot_tables/hc_*.tres` + `enemy_haunted_carnival.tres`, objets
  `data/items/hc_*.tres` (12) + `key_hc_director.tres`, icônes SVG `build_hc_icons.py`.
- **Pré-rendu** : `tools/prerender/hc_scene.py` + `hc_pipeline.sh` (mêmes passes full / int / mask / occ,
  même projection que le mall), paquet `assets/prerender/haunted_carnival/<seed>/`, mini-carte,
  vignette `assets/ui/maps/haunted_carnival.png` (`build_map_thumbs.py`, recadrage de la mini-carte).
- **Tests** `tests/test_haunted_carnival.gd`.

## Changements dans les fichiers partagés
- `scripts/biomes/biome_registry.gd` : entrée `haunted_carnival` (BIOMES) + `hc_builder.gd` (DEF_SCRIPTS).
- `data/balance.cfg` : section `[haunted_carnival]` ; `[maps] only_ids` : `perm_carnaval_hante` ajouté
  quand le paquet 72 px/case est livré.
- `assets/ui/maps/build_map_thumbs.py` : fonction `haunted_carnival()`.
- `tools/prerender/export_layout.gd`, `scripts/dungeon/prerender_backdrop.gd` : aucun changement
  nécessaire (contrat `render_contract` et paquets par biome déjà génériques).

## Ce qui manque / suite
- Bestiaire propre `hc_*` (phase 2) : le roster est celui du centre commercial.
- Sous-sol « coulisses » (non fait : un seul étage).
- Gabarits d'aménagement (`furnisher.gd`) : les salles du carnaval sont meublées par règles simples.
- `[maps] only_ids` : `"perm_carnaval_hante"` ajouté en fin de liste (paquet 72 px/case livré et vérifié).

## Paquet livré
`assets/prerender/haunted_carnival/2025/` : ppc 72, inclinaison 38°, image 6048×9936, 60 tuiles webp,
23 intérieurs (un par bâtiment à toit), collisions (456 rectangles, 3 cases débloquées seulement),
occultation (58 tuiles), mini-carte, emprise. Rendu ≈ 94 min CPU (full 68 min, intérieurs 25 min).
Commande : `flock /home/claude/.blender_render.lock tools/prerender/hc_pipeline.sh 2025 <work> 72 10 6`, puis
`python3 tools/prerender/hc_grade.py <work>` (post-étalonnage : saturation, ombres violettes, forêt
assombrie, lueurs magenta / violettes au sol autour du chapiteau, de l'allée, du parvis, des manèges et
sous les lampadaires ; appliqué à l'identique à `full.png` et aux `b*_in.png`, originaux en `*_raw.png`),
puis `compose.py` et `make_minimap.gd`. Captures en jeu : `tools/prerender/hc_capture.tscn` (xvfb).

## Évaluation (planche, colonne de gauche)
| Itération | Note | Principal écart |
|---|---|---|
| 1 | 4,5 | rectangle plat, roue à plat, rails seulement en bordure |
| 2–3 | 5,5 | roue debout lumineuse, rails plus épais, encore très vide |
| 4–5 | 6,0 | bosquets dans les enclos, tête de clown face caméra |
| 6 | 6,5 | bâtiments en dur (brique, toits de tôle), forêt dense |
| 7 | 7,0 | chapiteau 32×24 à gradins et escalier, contour mordu par la forêt, boucle de rails à travers le parc |
| final + étalonnage | **7,5** | (détail dans le rapport) |

## Limites connues
- Bandeau de salle de `raid.gd` (`FloorLayout.room_at`) : au centre du chapiteau il affiche « Allée des
  Lumières » (boîte de l'allée plus petite que celle de l'ovale). Le constructeur et le peupleur utilisent
  `hc_plan.gd room_grid()` (ovale correct). Corriger en scindant l'allée changerait le peuplement déjà rendu :
  à faire au prochain rendu.
- Flaques (matériau `water`) un peu trop bleues dans le rendu.
- Génération ≈ 40–57 ms/étage selon la charge de la machine (3 agents sur 2 cœurs) ; < 50 ms au calme.
