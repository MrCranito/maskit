# Carnaval hanté (`haunted_carnival`, préfixe `hc_`)

Planche : `docs/reference/cartes_2.png`, colonne de gauche (x 0‑535). Monde
`data/worlds/world_04_haunted_carnival.tres` (« Carnaval hanté »), carte `data/maps/perm_carnaval_hante.tres`
(`perm_carnaval_hante`, difficulté 2, nuit).

## Ce qui est fait
- **Plan** (`scripts/biomes/haunted_carnival/hc_plan.gd`) : parc 76×90 (refonte « Mac » d'après la planche, voir plus bas ; ancien plan 72×126), un seul étage (0, pré-rendu).
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
`assets/prerender/haunted_carnival/2025/` (plan 76×90) : ppc 72, inclinaison 38°, image 6336×7344, 56 tuiles webp,
15 intérieurs, collisions 423 rectangles (2 cases débloquées), occultation, mini-carte, emprise. Rendu Metal (Mac M4) :
full 188 s, intérieurs 53 s, total ≈ 4 min 15 + étalonnage/compose ≈ 2 min.
Commande : `source tools/prerender/mac_env.sh && flock "$BLENDER_LOCK" tools/prerender/hc_pipeline.sh 2025 <work> 72 16`
(le pipeline appelle maintenant `hc_grade.py` avant `compose.py`). Fichiers périmés de l'ancien paquet (in_15…30,
tuiles/occultation des rangées 8–9) supprimés. Captures en jeu (macOS, fenêtré) :
`godot --path . --resolution 1280x720 res://tools/prerender/hc_capture.tscn -- 2025 <dir> ["x,y;…"] [zoom]`.
Vignette `assets/ui/maps/haunted_carnival.png` régénérée (`build_map_thumbs.haunted_carnival()`).

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

## Refonte « planche » (session Mac, 30/10/2026)
Objectif : ≥ 9/10 de ressemblance avec la colonne gauche de la planche, priorité lumière et profondeur des matières.
Itérations d'aperçu (ppc 16, 4 échantillons, Metal ≈ 15 s par carte) dans le dossier de travail hors dépôt.

### Plan (hc_plan.gd)
- **76×90** au lieu de 72×126 : rapport largeur/hauteur de l'image (marge comprise) 0,86, celui de la planche (0,89).
- Disposition calquée sur la planche : grande roue NO, pavillon/sortie au nord au bout de l'allée du Belvédère,
  **enceinte de pierre rectangulaire** (`ENC_RECT`) autour du chapiteau avec **quatre bâtiments d'angle en ruine
  ouverts** (`ENC_HALLS`, vus en coupe, intérieurs visibles) séparés par les **escaliers nord et sud**, murs bas est/ouest
  percés au milieu ; chapiteau rond 19×15 (`TENT_R` 9,5×7,5) dans la cour ; place ovale autour ; allée des Lumières
  jusqu'au **portail à tête de clown** et au parvis (sud) ; cours des tasses (SO) et du carrousel (SE) ; chemins des
  roulottes ; bande nord laissée à la forêt (pas de stand avec `y < 5`).
- Sorties (extraction) : pavillon nord + sortie de secours est (`EXIT_NAMES`).
- Montagnes russes : tracé OUVERT (entre et sort du cadre au sud-ouest / sud-est), plus sinueux, pylônes dans la cour NE.
- Tailles : halls 7–9 cases, tentes 8–9, roulottes 7–8 (la roulotte du Directeur doit loger 2 coffres + gardes).
- Portes : la règle « pas de porte sur la façade extérieure du portail » est limitée aux colonnes du portail.
- balance.cfg `[haunted_carnival]` : `hc_hall_roof_chance` 1.0 → **0.35** (la plupart des halls vus en coupe, comme
  la planche).

### Scène (hc_scene.py)
- Matériaux v2 (`build_materials_v2`) : **dalles Voronoï** (joints creux, arêtes ébréchées, teinte par pierre,
  flaques brillantes qui reflètent les néons, mousse), **pierre de taille** (nœud Brick, coulures, lichen),
  **bardeaux** (rangées, mousse), **bois peint écaillé** (lames, peinture qui part par plaques), **toiles
  rayées délavées** (trame, coulures, plis), **aiguilles de sapin** ; couleurs désaturées (rouge sombre / blanc sale).
- Chapiteau : cône fermé à lés affaissés (relief des rayures), tambour haut **rose lumineux** à fenêtres (dans l'objet
  toit : caché en passe int), deux bandeaux néon magenta, couronne de lumières basses magenta / violet au pied.
- Enceinte : bâtiments d'angle en pierre ocre à merlons, contreforts à braseros, escaliers monumentaux.
- Tête de clown : sphère déformée (orbites, arcades, pommettes, rictus), poids de zones par sommet (attribut `zw`)
  lus par le matériau, dents, lèvres, mèches en pointes, éclairage latéral + par en dessous.
- Forêt de sapins dense (`build_forest`) dans la marge et les enclos hors jeu, jamais devant une case praticable,
  basse près des montagnes russes. Lune à l'ouest-sud-ouest (faces visibles modelées).
- Grande roue néon violet/magenta à ampoules chaudes ; montagnes russes rouges plus épaisses et plus hautes.
- Lanternes sur poteaux (≈ 60 flaques de lumière orangée), guirlandes et confettis réduits, fouillis sombre au sol.
- Stands : 55 % en appentis de bardeaux sombres (la toile rayée ne reste qu'en lambrequin).

### Étalonnage (hc_grade.py, désormais appelé par hc_pipeline.sh)
- Balance globale R×0,86 / B×0,95 (R:G:B de la planche), saturation 1,0, forêt bleu nuit (OUT_K 0,95),
  **halo atmosphérique** et **clarté** (contraste local à l'échelle de la case) calculés sur l'image entière réduite
  (aucun raccord entre bandes ni entre patchs d'intérieur).

### Évaluation (10 critères, compare_N.png)
| Itération | Note | Principal changement / écart restant |
|---|---|---|
| 1 (état hérité) | 4,5 | plan 72×126 trop étiré, chapiteau rouge/blanc ouvert, forêt plate, rendu « jouet » |
| 2–3 | 5,2 | plan 76×90, enceinte rectangulaire, chapiteau fermé |
| 4–8 | 5,6–6,0 | matériaux v2, forêt, lanternes, couleurs désaturées |
| 9–15 | 6,1–6,3 | balance de couleurs mesurée (stats régionales), halo, clarté, lune |
| 16–20 | 6,3–6,4 | tête de clown sculptée, halls ouverts, montagnes russes visibles |
| 21–23 | 6,45 | tracé ouvert des montagnes russes, toiles assombries — plafond atteint |
| **final 72 px/case** | **6,5** | voir détail ci-dessous |

Détail final (sur 10) : plan/composition 7 · éléments signature 6,5 · intérieurs 6,5 · abords 6 · palette 7 ·
lumière 6 · matières 5,5 · volume/angle 6,5 · lisibilité 7,5 · vignettes 6.

### Ce qui bloque au-dessus de ~6,5
- La planche est une illustration peinte (perspective plus rasante, détails peints partout) ; notre caméra est fixée
  à 38° « sol carré » par le jeu (test `tilt_deg = 38`) : façades moins visibles, tambour du chapiteau écrasé.
- Densité de détails : la planche a des centaines de micro-éléments éclairés ; nos bâtiments restent des volumes
  simples (stands, halls) malgré les matières v2.
- Tête de clown, grande roue et chapiteau sont reconnaissables mais plus « 3D jouet » que sculptés.
- Le rendu reste net/CG : pas de passe « peinte » (brume volumétrique, contours) ; le halo / la clarté de
  `hc_grade.py` n'en donnent qu'une partie.
