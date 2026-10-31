# Galeries Lumière (`mall`) — refonte du pré-rendu (Blender)

Planche : `docs/reference/cartes.png`, colonne de droite « Centre commercial abandonné » (x ≈ 880‑1312,
carte y ≈ 145‑925, vignettes Boutiques / Escaliers-Escalators / Couverts / Parking-Entrée). Monde
`data/worlds/world_03_mall.tres`, carte `data/maps/perm_galeries_lumiere.tres`, paquet
`assets/prerender/mall/2025/` (seed 2025 gardée : référencée par le paquet et la carte, plan inchangé).

## Pipeline
`tools/prerender/mall_pipeline.sh <seed> <work> [ppc=72] [samples=16] [margin=6]` :
`export_layout.gd` → `mall_scene.py` (passes mask, occ, puis full et int **par tranches reprenables**
sous `BLENDER_LOCK`, `SLICE_S` s) → **`mall_grade.py`** (nouveau) → `compose.py` → `make_minimap.gd`.
Vignette de sélection : `build_map_thumbs.mall()` recadre maintenant la mini-carte du paquet (repli :
illustration peinte).

## Ce qui a changé dans la scène (`tools/prerender/mall_scene.py`)
Plan, générateur, constructeur et populateur **inchangés** (même `tiles_md5`, mêmes collisions de plan).
- **Murs** : cloisons et murs extérieurs **minces** (demi-épaisseur 0,2 / 0,3 case, `MALL_WALL_T`,
  `MALL_WALL_T_EXT`), poteau + bras vers les murs voisins, sol de la pièce dessous (trottoir côté rue) ;
  arase claire légèrement émissive (`MALL_TOP_EMIT`) = le liseré clair des murs de la planche ; faces
  brun sombre, plinthe ; hauteurs relevées (cloisons 1,75, extérieur 2,0, boutiques à plafond 1,95,
  `MALL_H_*`). La collision du jeu reste la case entière.
- **Parking** : bordure en muret bas (0,5) au lieu d'un mur plein, bitume plus clair, voitures plus
  grandes (débordent un peu de l'emprise 2 × 1), voiture rouge forcée près de l'entrée.
- **Rues** (hors jeu) : trottoirs dallés, rue au sud du parking, voitures garées le long des façades,
  lampadaires, bennes et sacs poubelle.
- **Lumière** : plafonniers plus petits, plus bas et plus nombreux (flaques de lumière nettes),
  carrelage plus lisse (`MALL_GAL_ROUGH` 0,2 : reflets ponctuels des plafonniers), appliques murales
  côté galerie (plaque émissive + point chaud), boutiques en lumière ambrée tamisée (peu de néons
  colorés au sol), arcade moins saturée, fontaine moins lumineuse.
- **Profondeur** : occlusion ambiante dans la couleur de base de tous les matériaux (`MALL_AO`,
  `MALL_AO_DIST`) ; détails plats invisibles aux rayons secondaires (pas de carrés sombres sous les
  taches).
- **Atrium** : muret-jardinière haut (1,1) à arase claire, palmiers, massifs bas au pied côté intérieur,
  sol d'atrium distinct (`tiles_atr`), vasque de fontaine resserrée.
- **Fouillis non bloquant** `_junk` (hors masque d'emprise, ≤ 0,34 de haut) : gondoles couchées,
  tables renversées et chaises, banquettes, cartons, tas de vêtements, comptoirs renversés — dans
  les boutiques (13 %/case) et en îlots de 1‑3 meubles dans la galerie (5,5 %/case).

## Étalonnage (`tools/prerender/mall_grade.py`, nouveau)
Appliqué à `full.png` et aux patchs `b<id>_in.png` (même résultat au pixel près, raccords invisibles) ;
originaux gardés en `*_raw.png` (`grade.json` : un nouveau rendu redevient l'original). Appariement de
la luminance sur les quantiles de la carte de la planche (statistiques sur le cadrage de la planche),
transfert de teinte par tranche de luminance, boutiques plus sombres et plus chaudes, dehors gris-bleu
nuit désaturé, vignettage, second appariement, noirs relevés vers le brun-violet, épaule ambrée des
hautes lumières, halo diffus, clarté. Réglages `MALL_GRADE_*` (MATCH 0,75, MATCH2 0,6, CHROMA 0,7,
SAT 1,08, DARK_IN 0,72, OUT 0,6, VIG 0,6, HAZE 0,3, LIFT 0,12, SHOULDER 0,6, CLARITY 0,35).

## Évaluation (aperçus 24 px/case, 8 éch. ; `compare_N.png` : planche à gauche, rendu à droite)
Notes /10 sur 10 critères : plan, éléments signature, intérieurs, extérieurs, palette, lumière,
profondeur/matières, volume/angle, lisibilité en jeu, vignettes.

| It. | Changement principal | Note |
|---|---|---|
| 0‑1 | paquet de départ (rendu plat, murs épais gris, sol crème uniforme, fontaine bleue, extérieurs noirs) | 4,9 |
| 2 | `mall_grade.py` (luminance + teinte calées sur la planche) | 5,3 |
| 3‑4 | appliques, plafonniers plus denses, murs plus hauts, rues et lampadaires, voitures garées, sols des boutiques plus sombres | 5,8 |
| 5 | fouillis `_junk` (boutiques et galerie), muret de l'atrium | 6,0 |
| 6‑7 | occlusion ambiante, fontaine sombre, carrelage lisse (reflets) | 6,2 |
| 8‑9 | cloisons et murs extérieurs minces | 6,3 |
| 10‑12 | parking ouvert (muret), bitume clair, rue sud ; statistiques d'étalonnage sur le cadrage de la planche, noirs relevés, épaule ; atrium : massifs, toits sombres | 6,4 |
| 13‑14 | murs plus hauts, arases claires émissives, dehors désaturé | 6,65 |
| 15‑16 | sol d'atrium, voiture rouge, îlots de meubles, boutiques en lumière ambrée | 6,9 |
| 17‑19 | trottoirs dallés, bennes ; plafonniers plus petits (flaques nettes), carrelage 1,5 case, meubles ocre | 7,0 (plafond : +0,07, +0,10, −0,04) |

Plafond atteint à ≈ 7,0 (3 itérations d'affilée sous +0,15) : final lancé avec la version 19.

## Rendu final
`mall_pipeline.sh 2025 <work> 72 16 6` (Mac M4 / Metal) : passe full 5616 × 9792 en 283 s, intérieurs
15 s, 26 min de bout en bout (attente des verrous partagés comprise). Paquet
`assets/prerender/mall/2025/` : 72 px/case, 60 tuiles, 3 intérieurs, 3,6 Mo ; collisions par emprise :
8 cases débloquées (< 60), mini-carte et vignette `assets/ui/maps/mall.png` régénérées.
Tests : `test_mall.gd` 33/33, `test_prerender_streaming.gd` 2/2, `test_turrets.gd` 20/20.
Captures en jeu : `tools/prerender/mall_shots.gd` (+ `mall_shots_driver.gd`).

**Note finale (72 px/case) : 7,0 / 10** (départ 4,9) — plan 7,0 ; éléments signature 7,2 ; intérieurs
7,0 ; extérieurs 6,5 ; palette 7,3 ; lumière 7,2 ; profondeur/matières 7,1 ; volume/angle 6,3 ;
lisibilité 7,6 ; vignettes 6,0.

Ce qui plafonne sous 7,5 : la planche est une vue en **perspective** (faces des murs visibles de tous
les côtés, effet maquette), alors que la projection du jeu (orthographique inclinée de 38°, imposée)
ne montre que les faces sud ; le plan (galerie large, parking clos de 19 épaves, 3 boutiques à
plafond) est plus aéré et plus « plan d'architecte » que la planche, très dense en meubles bruns ; les
vignettes (intérieurs en perspective) ne sont qu'évoquées. Pistes : îlots de boutiques supplémentaires
dans la galerie (générateur), moins d'épaves au parking (populateur), mobilier modélisé plus riche.

## Fichiers partagés modifiés
- `assets/ui/maps/build_map_thumbs.py` : `mall()` recadre la mini-carte du paquet s'il existe (ajout
  en tête de fonction, l'illustration peinte reste le repli).
