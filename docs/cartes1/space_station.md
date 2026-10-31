# Station Kagami (`space_station`) — refonte Blender, passe lumière / matières

Planche : `docs/reference/cartes.png`, colonne du milieu (x 440‑875 ; carte y 145‑925 ; vignettes
Modules, Couloirs, Centre de contrôle, Gravité faible). Carte `data/maps/perm_station_kagami.tres`,
monde `data/worlds/world_02_space_station.tres`, paquet `assets/prerender/space_station/948725/`
(seed 948725 conservée : le jeu prend le paquet présent, aucune autre référence).

## Pipeline
`source tools/prerender/mac_env.sh && tools/prerender/ss_pipeline.sh 948725 <work> 72 16 6` :
export_layout → `ss_scene.py` (mask, full, occ, int) → **`ss_grade.py`** (nouveau) → `compose.py` →
mini‑carte. Le paquet est vidé avant un rendu complet (les anciens `in_*` / `o_*` ne sont pas
écrasés par compose).

## Changements
- **Plan** (`ss_cross.gd`) : ascenseurs, réduits et flanc non scellé du module nord n'ont plus de toit
  (pièces éclairées visibles, comme la planche) ; réglable `[space_station] cross_roof_lifts`,
  `cross_roof_closets`, `cross_roof_flank` (0 par défaut). 9 modules à toit au lieu de 14. Le labo
  scellé, l'armurerie et les salles des machines gardent leur toit.
- **Lumière** (`ss_scene.py`) : ciel ambiant quasi nul (espace) `SS_SKY 0.25→0.06`, soleil
  `1.5→0.9` ; places et coursives éclairées par un grand plafonnier rectangulaire chaud
  (`SS_HALL_RECT`, `SS_HALL_COL`, coursives `SS_CORR_K 0.5`) au lieu d'une grille de flaques
  blanches ; lampes sur les piles de fret (`SS_SPOT_E`) ; modules : plafonniers resserrés
  (`SS_ROOM_SZ`, `SS_ROOM_K`) + appliques du mur nord avec réglette visible (`SS_WALL_E`) → dégradé
  clair au fond de la pièce ; flaques colorées des voyants de porte (`SS_DOOR_E`, + magenta) ; teinte
  des lumières adoucie (`SS_LIGHT_TINT`) ; lumière de Terre venant de l'est (`SS_EARTHSHINE_D`).
- **Matières / profondeur** : occlusion ambiante dans sols et panneaux (`SS_AO`), relief des sols
  `SS_FLOOR_BUMP`, teinte par grande plaque (`SS_PLATE_VAR`), plaques 1 case, usure plus forte,
  taches d'huile sur les places (`SS_HALL_STAIN`, décalques exclus des rayons d'ombre/AO) ;
  métallique borné (`SS_METAL_K 0.4`, sinon noir dans le vide) ; arases de murs bleu nuit à liseré
  clair (aussi côté vide) ; toits de coque bleu nuit à rampe de hublots ; machinerie sous la coque
  (`SS_GREEBLE`, objet `skirt`, hors emprise).
- **Volume** : murs plus hauts (`SS_H_OPEN 1.7`, `SS_H_HULL 2.1`, `SS_H_ROOF 2.3`), réacteurs
  hauts côtelés (`SS_REACTOR_H 4.2`, coque plus claire, calotte nervurée, cœur réduit), anneau clair
  du dôme élargi, verre plus transparent (`SS_GLASS`).
- **Éléments signature** : Terre déplacée derrière la station (centre 40,50, r 46, éclairée du
  nord‑est, nuages fins, assombrissement au limbe), parabole nervurée, ailes solaires à 2 colonnes,
  conteneurs de fret 2×2 sur les places (`SS_HALL_BIG`, `SS_HALL_DENS`), caisses plus chaudes.
- **`ss_grade.py`** : appariement de luminance sur les quantiles de la planche, ombres bleu nuit,
  tons moyens neutres, occlusion de contact calculée sur le plan, contraste local, halo froid
  calculé sur l'image entière (patchs d'intérieur identiques au pixel près), vignettage. Idempotent
  (`*_raw.png` + `ss_grade_state.json`).
- Captures : `tools/prerender/ss_shots.gd` / `ss_shots_driver.gd` (fenêtre réelle).
- Vignette `assets/ui/maps/station_kagami_real.png` régénérée depuis la vue d'ensemble.

## Évaluation (10 critères, sévérité constante)
| It. | Changement | Note |
|---|---|---|
| 0 | état de départ : flaques blanches en grille, Terre centrée, toits gris rayés, réacteurs plats | 4,9 |
| 1‑5 | plafonniers hauts, Terre déplacée, AO, `ss_grade`, plafonniers rectangulaires des places | 5,5 |
| 6‑13 | ciel ambiant coupé, murs sombres, réacteurs côtelés, machinerie de coque, métal borné | 6,1 |
| 14‑19 | solaires, appliques murales, plaques 1 case, conteneurs 2×2, pièces sans toit | 6,3 |
| 20‑24 | coursives plus sombres, caisses chaudes, réglettes visibles, taches, contraste local | 6,4 |

Plafond atteint (3 itérations < +0,15). **Note finale (72 px/case) : 6,4 / 10** — plan 7,0 ;
éléments signature 7,0 ; intérieurs 5,8 ; extérieurs 6,2 ; palette 6,8 ; lumière 6,3 ;
matières 6,2 ; volume 5,8 ; lisibilité 7,3 ; vignettes 5,5.

Rendu final (Mac M4, Metal, 16 éch.) : full 5472×9216 en 183 s, intérieurs 59 s, 253 s de Blender,
≈ 23 min de bout en bout (attente des verrous partagés comprise) ; 54 tuiles, 9 intérieurs,
3,2 Mo ; 6 cases débloquées. `test_space_station.gd` 36/36.

## Limites
La planche est une peinture IA très dense (mobilier partout, contours peints, perspective
plus marquée sur les cylindres) ; la grille d'une case donne des murs épais et des places vastes
peu meublées (le mobilier y est contraint par les collisions) ; l'inclinaison est figée à 38° par le
jeu ; les tubes en escalier gardent un liseré de murs sombres ; les vignettes (intérieurs en
perspective) ne sont qu'évoquées par les patchs vus de dessus.
