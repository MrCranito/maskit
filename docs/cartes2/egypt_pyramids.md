# Les Pyramides d'Égypte (`egypt_pyramids`, préfixe `eg_`)

Planche : `docs/reference/cartes_2.png`, colonne de droite (x 1070‑1606). Monde
`data/worlds/world_06_egypt_pyramids.tres` (« Les Pyramides d'Égypte »), carte
`data/maps/perm_pyramides_egypte.tres` (`perm_pyramides_egypte`).

## Plan (surface, étage 0, un seul étage)
`scripts/biomes/egypt_pyramids/eg_plan.gd` — grille portrait 72 × 88, déterministe par seed, structure
indépendante de la difficulté (même paquet pré‑rendu pour toutes).
- **Grand temple** central (enceinte 28 × 28) : galerie à colonnes, 4 chambres d'angle (toit),
  mur intérieur, cour du sanctuaire, **sanctuaire** carré au cœur (`boss`, archétype `sanctuary`,
  porte de bronze au sud), portes monumentales nord/sud (pylônes à oriflammes).
- **4 temples d'angle** (18 × 16, NW/NE/SW/SE) : cour à ciel ouvert, portail de 2 cases vers le
  centre, chambres autour (tombes, couloirs piégés, salles des gardes, offrandes, embaumement,
  scribes, galerie des statues ; ~75 % avec toit). L'un d'eux (seed) abrite la **chambre du
  trésor** (`super_loot`, dalle scellée `key_eg_treasury`, coffres dorés `eg_gold_chest`).
- **Salle hypostyle** au nord (toit, colonnes 3 × 3), **avenue des sphinx** au sud (arrivée,
  deux colosses assis), **pyramides** (4 grandes aux coins, 2 petites décalées par seed, entrée
  sombre), obélisques, palmiers, rochers, ruines ensablées, dunes (`landmarks`).
- Extérieurs : oasis (repos), campement des pilleurs (extraction NE), dunes de l'ouest
  (extraction W), parvis, nécropoles.
- Contrat de rendu `render_contract` : modules, colonnes, torches, enceinte/inner/sanctuaire,
  pylônes, temples, hypostyle, avenue, petites pyramides, landmarks, gates.

## Peuplement (`eg_populator.gd`)
Décors par rôle (`PROPS`), conteneurs (`CONTAINERS`), cachettes (`HIDING`), ennemis (roster
provisoire `fw_*` du monde + surcharges par rôle `ROLE_ROSTER`), boss `fw_sheriff` garanti au
sanctuaire, élites `fw_deserter` / `fw_buffalo` (BestiaryRules). Passages de 2 cases (portails,
portes monumentales) réservés. Réglages : `[egypt_pyramids]` et `[bestiary_egypt_pyramids]`.

## Constructeur (`eg_builder.gd`)
API WorldBuilder : `get_doors`, `get_stairs_areas` (vide), `stairs_entered`, `get_room_at_world`,
`set_stairs_cooldown`, `get_roofs`, `get_props`, `get_wall_body`, `prerender_hide`. Rendu 2D de
repli dessiné en code (sable, dalles, murs de grès 3/4, repères, toits plats `EgRoof` qui
s'effacent), portes `eg_door.gd` (stone / bronze / sealed), décors `eg_prop.gd` (atlas
`assets/sprites/egypt_pyramids/atlas.png`, `art/blender/egypt_pyramids/build_eg_props.py`).

## Butin
Conteneurs `eg_jar`, `eg_sarcophagus`, `eg_chest`, `eg_gold_chest`, `eg_altar`, `eg_basket`,
`eg_mummy`, `eg_corpse` (sprites `assets/sprites/egypt_pyramids/containers/`, tables
`data/loot_tables/eg_*.tres`, `enemy_egypt_pyramids.tres`) ; cachettes `eg_sarcophagus_hide`,
`eg_big_jar`, `eg_hay_cart`. Objets `data/items/eg_*.tres` (15) + clef `key_eg_treasury`
(icônes `art/blender/egypt_pyramids/build_eg_icons.py`). Poids d'armes = formule de
`tools/gen_weapons.py` (paliers rich / medium / enemy).

## Pré‑rendu
`tools/prerender/eg_pipeline.sh <seed> <work> [ppc] [samples]` → `export_layout.gd` →
`eg_scene.py` (passes mask / full / occ / int, projection `ground_square`, tilt 38°) →
`compose.py` → `assets/prerender/egypt_pyramids/<seed>/` → `make_minimap.gd`.
Captures et comparaisons : `scratchpad/shots/egypt/` (`compare_N.png`, `M_overview.png`,
`M_ingame_1..3.png`, script `tools/prerender/eg_shots.gd` sous xvfb).

## Fichiers partagés modifiés
- `scripts/biomes/biome_registry.gd` : entrée `egypt_pyramids` dans `BIOMES`, `eg_builder.gd`
  dans `DEF_SCRIPTS`.
- `assets/ui/maps/build_map_thumbs.py` : fonction `egypt_pyramids()` + appel.
- `data/balance.cfg` : sections `[egypt_pyramids]`, `[bestiary_egypt_pyramids]` ; `[maps] only_ids`
  (ajout de `perm_pyramides_egypte` une fois le paquet 72 px/case livré).
- `export_layout.gd`, `prerender_backdrop.gd` : aucun changement nécessaire (génériques).

## Évaluation (voir le rapport final)
