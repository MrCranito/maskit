# Les Pyramides d'Égypte (`egypt_pyramids`, préfixe `eg_`)

Planche : `docs/reference/cartes_2.png`, colonne de droite (x 1070‑1606). Monde
`data/worlds/world_06_egypt_pyramids.tres` (« Les Pyramides d'Égypte »), carte
`data/maps/perm_pyramides_egypte.tres` (`perm_pyramides_egypte`).

## Plan (surface, étage 0, un seul étage)
`scripts/biomes/egypt_pyramids/eg_plan.gd` — grille portrait 72 × 88, déterministe par seed, structure
indépendante de la difficulté (même paquet pré‑rendu pour toutes). Depuis l'itération 30 : sanctuaire
**à ciel ouvert** (plus de toit : dais à l'ankh d'or au centre, comme la planche) et peu de chambres à
toit (probabilité `roof_p × 0.22`, 7 bâtiments pour la seed 2026 : trésor, corps de garde, 4 chambres).
Plan en croix (« plan v3 », d'après la planche) :
- **Grande cour centrale à double enceinte** (enceinte 30 × 30, bande de chambres de 3 cases
  autour d'une cour à ciel ouvert, anneau de colonnes) et **sanctuaire** 12 × 12 au cœur (`boss`,
  archétype `sanctuary`, toit doré étagé à cartouche ankh, porte de bronze au sud).
- **Temple nord** (hypostyle, cour à colonnes) et deux **ailes** est/ouest accolées à l'enceinte ;
  **4 pavillons détachés** (NW, NE, SW, SE) séparés de l'ensemble par des passages de sable,
  chacun avec sa cour et ses chambres (tombes, couloirs piégés, salles des gardes, offrandes,
  embaumement, scribes, galerie des statues ; toits sur une partie des chambres). L'un d'eux
  (seed) abrite la **chambre du trésor** (intérieur ≥ 3 × 3, `super_loot`, dalle scellée
  `key_eg_treasury`, coffres dorés `eg_gold_chest`).
- **Porterie** sud (deux pylônes à oriflammes), **escalier monumental** flanqué de deux grands
  **sphinx** (colosses assis), **avenue** d'arrivée (spawn au sud).
- **Pyramides** : 3 grandes (NW, NE, SW) et 3 petites, obélisques, bosquets de palmiers, groupes de
  rochers, ruines ensablées, dunes (`landmarks`). Oasis (repos), deux points d'extraction
  (est et ouest).
- Contrat de rendu `render_contract` : modules, colonnes, torches, enceinte/inner/sanctuaire,
  pylônes, temples, hypostyle, avenue, petites pyramides, landmarks, gates.
- Le sanctuaire reste la salle `boss` (archétype `sanctuary`) mais n'est plus un bâtiment (pas de
  toit ni de patch d'intérieur).

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
`eg_big_jar`, `eg_hay_cart`. Objets `data/items/eg_*.tres` (14, dont le sceptre heka `eg_pharaoh_scepter` — pas de masque) + clef `key_eg_treasury`
(icônes `art/blender/egypt_pyramids/build_eg_icons.py`). Poids d'armes = formule de
`tools/gen_weapons.py` (paliers rich / medium / enemy).

## Pré‑rendu
`tools/prerender/eg_pipeline.sh <seed> <work> [ppc] [samples]` → `export_layout.gd` →
`eg_scene.py` (passes mask / full / occ / int, projection `ground_square`, tilt 38°) →
`eg_grade.py` (étalonnage post-rendu sans Blender : appariement de la luminance sur les quantiles
de la planche, teinte ocre dorée, ombres brun chocolat, intérieurs assombris, taches orange des
torches/braseros, halo du sanctuaire, vignettage chaud ; originaux gardés en `*_raw.png`) →
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

## Évaluation
Itérations basse résolution (12 px/case, 6 échantillons) comparées à la planche
(`scratchpad/shots/egypt/compare_N.png`). Étapes décisives : plan en croix v3 (it. 13‑16),
étalonnage par appariement de luminance `eg_grade.py` (it. 19‑21), géométrie « ruine » (arases
érodées, brèches, blocs tombés, piliers d'angle), correction de la matière d'arase (sable parasite),
intérieurs meublés, toits en dalles‑poutres, sphinx couchés, pyramides à gradins, parvis ensablé,
marge de rochers / palmiers (it. 22‑29), halos de torches resserrés et sable ocre contrasté (29h).
Note retenue avant le final : ≈ 7,5 / 10 (coordination : ~7,2 sur it. 29 avant étalonnage 29h).

## Refonte de la lumière et des matières (itérations 30‑49, session Mac / Blender 5.2 Metal)
Aperçus 12 px/case (4 éch.) puis 24 px/case (8 éch.), `compare_N.png` (planche à gauche, rendu à
droite) dans le dossier de travail de la session. Notes honnêtes /10 (moyenne de 10 critères :
plan, éléments signature, intérieurs, extérieurs, palette, lumière, matières, volume, lisibilité,
vignettes) :

| It. | Changement principal | Note |
|---|---|---|
| 29 (départ, revu) | pyramides en escalier, soleil à l'ouest, sable orange uniforme, toits gris | ≈ 5,8 |
| 30 | soleil à l'est‑nord‑est (ombres vers l'ouest comme la planche), pyramides lisses, palmiers en rubans, sanctuaire ouvert à dais d'ankh | 6,2 |
| 31‑33 | sable à rides (sinus gauchi + bump), murs et dalles de grès plus chauds/sombres, palmiers plus grands, moins de toits | 6,6 |
| 34 | colosses assis au némès rayé (à la place des sphinx « blob »), folioles des palmes, pyramides à grands blocs et coulures | 6,7 |
| 35‑37 | ruine moins bruitée (brèches et blocs d'arase réduits), sanctuaire bas et sombre, flammes orangées, second appariement de luminance + ombres refroidies (`eg_grade.py`) | 7,0 |
| 38‑40 | mobilier des chambres (`build_furnish` : sarcophages, coffres, étagères, râteliers, statuettes, tapis), plaques‑emblèmes des cours, lumières de torches dosées, toits en terrasse | 7,2 |
| 42‑44 | soleil plein est (face sud des pyramides en lumière rasante, face est éclatante, face ouest à l'ombre), intérieurs désaturés | 7,4 |
| 45‑47 | halo doré diffus (bloom basse résolution commun aux patchs), correction d'un bug de matière (FLOOR scalaire sur un vecteur → fausses rayures diagonales dans le sable) | 7,4 |
| 48‑49 | débris variés sur le sable (tambours de colonnes, touffes, blocs), pyramides qui ne débordent que vers les bords de carte (emprise cohérente : 0 case débloquée) | 7,5 |

Réglages retenus : soleil `EG_SUN_X/Y/Z = -0.85 / -0.05 / -0.55`, ciel mauve‑bleuté 0,45,
torches `EG_LIGHT = 170`, étalonnage `DARK_IN 0.5`, `DESAT_IN 0.18`, `SHADOW 0.12`, `VIG 0.5`,
`MATCH2 0.75`, `COOL 0.5`, `HAZE 0.22`.

**Rendu final** (`eg_pipeline.sh 2026 <work> 72 16 6`, Mac M4 / Metal) : passe full 6048 × 7200 en
150 s, intérieurs 18 s, 15 min 22 s de bout en bout (attente des verrous partagés comprise) ; paquet
`assets/prerender/egypt_pyramids/2026/` (72 px/case, 48 tuiles, 7 intérieurs, 6,1 Mo), collisions par
emprise sans case débloquée, mini-carte et vignette `assets/ui/maps/egypt_pyramids.png` régénérées
(`build_map_thumbs.egypt_pyramids(<vue d'ensemble>)`). `tests/test_egypt_pyramids.gd` : 22/22.
Note finale (rendu 72 px/case) : **7,5 / 10** — plan 7,5 ; éléments signature 8,2 ; intérieurs 6,8 ;
extérieurs 7,4 ; palette 7,8 ; lumière 7,8 ; matières 7,3 ; volume 7,4 ; lisibilité 7,6 ; vignettes 7,0.

Ce qui plafonne sous 9 : la planche est une peinture IA d'une densité de micro‑détails (mobilier,
statues, objets colorés partout, contours peints) qu'un rendu 3D procédural ne reproduit pas sans
une bibliothèque d'objets bien plus riche ; le plan en grille (murs d'une case, nombreuses petites
chambres) donne une lecture plus « labyrinthe » que les grandes salles de la planche ; les vignettes
(intérieurs en perspective) ne sont qu'évoquées par les patchs d'intérieur vus de dessus.
