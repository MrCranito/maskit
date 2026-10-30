# Far West — Dust Creek (refonte du pré-rendu)

Planche : `docs/reference/cartes.png`, colonne de gauche (x 0‑435 ; carte y ≈ 145‑925 ; vignettes
Bâtiments / Couverts / Rochers / Train). Monde `data/worlds/world_01_far_west.tres`, carte
`data/maps/perm_dust_creek.tres`, paquet `assets/prerender/far_west/642439/` (même seed, même plan :
`tiles_md5` inchangé, le générateur commun `scripts/dungeon/*` n'est pas modifié).

## Pipeline
`source tools/prerender/mac_env.sh && tools/prerender/fw_pipeline.sh 642439 <work> [ppc=72] [samples=16] [margin=4]`
→ `export_layout.gd` → `fw_scene.py` (passes mask, occ, full par morceaux reprenables, int) →
`fw_grade.py` (étalonnage sans Blender, originaux en `*_raw.png`) → `compose.py` → `make_minimap.gd`.
Aperçu : `fw_pipeline.sh 642439 <work> 12 4`. Passe supplémentaire `pv:cx;cy;dist;yaw;pitch;lens;w;h`
(vue en perspective) pour la vignette du hub `assets/ui/maps/dust_creek_real.png`.
Captures en jeu : `tools/prerender/fw_shots.gd` (+ `fw_shots_driver.gd`).

## Changements (fw_scene.py)
- Palette de la planche : tôle galvanisée grise dominante (plus de bleu), ~1/4 de toits en planches
  délavées, un ou deux toits rouges (`balance_roofs`) ; ciel d'appoint moins bleu (`FW_SKY_COL`).
- Grands bâtiments (≥ 9 cases) : toits en deux corps accolés (matières / hauteurs différentes).
- Sol : sable ocre orangé, taches sombres « peintes », terrain hors rues plus sombre (rues lisibles),
  ornières marquées, micro-relief (grain, gravillons, rides) lisible à 72 px/case (`FW_MICRO`,
  `FW_GROUND_BUMP`, `FW_OFFPATH`).
- Rochers plus orangés ; marges hors carte en amas de gros rochers arrondis avec buissons et arbres.
- Train : wagons rouges (toits rouges), traverses délavées, ballast plus clair.
- Puits creux (margelle de blocs, eau sombre visible).
- Couverts : fouillis plus dense (`FW_CLUTTER_K` 0.7), couverts isolés dans les rues
  (`FW_OPEN_COVER_K`), 9 charrettes abandonnées sur 2 cases (`FW_CARTS`) ; tous passent par le
  même test de connexité locale et le masque d'emprise → collisions cohérentes.
- Trottoirs de planches plats le long des pignons (non bloquants, sous le plan de coupe du masque).
- Végétation plus fournie dans les terrains vagues (traversable, hors masque).
- Intérieurs : cloisons continues et basses, mobilier adossé aux murs (dans les cases murées),
  débris plats au sol, tapis ; passe « int » : le toit reste invisible mais garde son ombre, éclairage
  d'ambiance sous le toit (`FW_IN_FILL`) et lampes à pétrole (`FW_LAMP_W`).

## Étalonnage (fw_grade.py)
Appariement de luminance sur les quantiles de la planche (`MATCH 0.9`), clarté (contraste local
calculé sur l'image entière), teinte ocre sur les tons chauds seulement (les toits gris restent
gris), ombres brun chaud, halo chaud diffus, vignettage léger. Champs globaux calculés une fois sur
`full.png` et appliqués aux patchs d'intérieur avec leur décalage (raccords invisibles).

## Évaluation (notes /10, même sévérité)
| It. | Changement | Note |
|---|---|---|
| 0 (paquet d'origine) | toits bleu saturé, sable pâle, sol lisse, intérieurs nus | 5,5 |
| 2 | palette (tôle grise, sable orangé) + `fw_grade.py` | 5,8 |
| 3‑5 | toits en deux corps, taches de sol, amas de rochers en marge | 6,2 |
| 6‑7 | train rouge, cloisons continues, mobilier | 6,3 |
| 8‑10 | micro-relief du sol, puits creux, trottoirs | 6,6 |
| 11‑12 | couverts et charrettes, vignettes en perspective | 6,95 |
| 13‑16 | intérieurs à l'ombre du toit + ambiance + lampes | 7,1 |
| 17‑19 | rues lisibles (terrain vague plus sombre), végétation | 7,2 |

Final 72 px/case (16 éch.) : **7,2 / 10** — plan 6,5 ; éléments signature 7,6 ; intérieurs 7,0 ;
extérieurs 7,0 ; palette 7,7 ; lumière 7,1 ; matières 7,4 ; volume 7,0 ; lisibilité 7,4 ; vignettes 7,0.
Rendu final : 4 min 22 s de bout en bout (Mac M4 / Metal), paquet 5,3 Mo, 35 tuiles, 19 intérieurs.

Ce qui plafonne sous 7,5 : le plan est imposé par le générateur commun (19 grands bâtiments espacés,
larges rues vides) alors que la planche montre une trentaine de petites maisons serrées, des cours
clôturées et des chariots partout ; ajouter ces obstacles changerait le plan jouable (collisions,
`tiles_md5`). Une partie de la densité de la planche (chariots, caisses, cadavres) est apportée en jeu
par les conteneurs, qui ne sont pas dans le fond pré-rendu.
