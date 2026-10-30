# Les Terres gelées (`frozen_lands`, préfixe `fl_`)

Carte permanente `perm_terres_gelees` (monde `data/worlds/world_05_frozen_lands.tres`), colonne du
milieu de `docs/reference/cartes_2.png` : base militaire abandonnée en croix sur un plateau de glace
entouré d'eau noire et de banquise, laboratoire circulaire aux cristaux bleus au centre (salle du
boss), bunkers, laboratoires, baraquements, hangars, héliport, postes de garde hexagonaux, dômes
d'observation, navire brise-glace échoué, épave. Planche visée ≥ 70 % de similitude.

## Fichiers (propriété : agent Terres gelées)
| Rôle | Fichier |
|---|---|
| Monde | `data/worlds/world_05_frozen_lands.tres` (roster provisoire `ss_*`, boss `ss_architect`, élites `ss_drone_tieur`/`ss_atlas`, un seul étage 0) |
| Carte | `data/maps/perm_terres_gelees.tres`, vignette `assets/ui/maps/frozen_lands.png` |
| Générateur | `scripts/biomes/frozen_lands/frozen_lands_generator.gd` (API `generate_run` / `generate_floor` / `find_floor`), plan `fl_plan.gd` (76×112, croix sur plateau, contrat de rendu en métadonnée `render_contract`), peuplement `fl_populator.gd`, réglages `fl_config.gd` (section `[frozen_lands]` de balance.cfg, repli `[generator]`) |
| Constructeur | `frozen_lands_builder.gd` (API WorldBuilder + `get_roofs`, `prerender_hide`, `get_props`, `get_wall_body`), portes `fl_door.gd`, décors (collisions) `fl_prop.gd`, `enemy_kinds.gd` (vide : planches `ss_*`) |
| Butin | objets `data/items/fl_*.tres` (13 objets + clefs `fl_key_lab`, `fl_key_bunker`), tables `data/loot_tables/fl_*.tres` + `enemy_frozen_lands.tres`, générateur `tools/dev/gen_frozen_lands_loot.py` |
| Sprites | `assets/sprites/frozen_lands/containers/` (8 conteneurs fermé/ouvert + 3 cachettes), source `art/blender/frozen_lands/build_containers.py` |
| Pré-rendu | `tools/prerender/fl_scene.py` (scène Blender, passes mask/full/occ/int), `fl_pipeline.sh`, paquets `assets/prerender/frozen_lands/<seed>/` |
| Outils | `tools/prerender/fl_dump.gd` (plan ASCII), `fl_capture.tscn/.gd` (captures en jeu sous xvfb) |
| Tests | `tests/test_frozen_lands.gd` |

## Structure du plan (fl_plan.gd)
- Base COMPACTE en croix (les blocs se touchent par leurs murs) : passerelle nord (porte nord →
  cour), cour intérieure autour du **laboratoire circulaire** (R 10,5 ; salle `boss`, ouverte sur
  les 4 axes, grand cristal `fl_crystal_core` au centre), passerelle sud → rampe d'accès → **pont
  d'accès au-dessus de l'eau** (apparition au bout du pont). Blocs BSP : nord (labos, baraquements,
  commandement), ailes est/ouest (réfectoire, infirmerie, bunkers, entrepôts…), sud (hangars avec
  hélicoptère, garage des autoneiges).
- **4 postes de garde hexagonaux aux angles** (`fl_tower`), reliés à la base par des galeries
  couvertes (`walkway` horizontales, escaliers vers la neige des deux côtés) ; dômes
  d'observation (`fl_dome`) NO (près de l'héliport) et SE (près du ponton).
- Plateau : emprise de la base dilatée de `PLAT_DIL` cases avec bruit à facettes (bord anguleux,
  falaise de glace = rangée de murs), eau (`VOID`) tout autour, entaille au NE (navire pris dans la
  banquise) ; peu de neige nue. Îlots de neige inaccessibles → eau.
- Fermés (toit) : bunkers (`fl_bunker`), hangars (`fl_hangar`), postes de garde, dômes ; portes
  `DoorNode` jamais dans le mur nord d'un module à toit.
- Super-loot : labo cryogénique scellé (bloc nord, `fl_key_lab`) + armurerie du bunker (aile,
  `fl_key_bunker`), une seule porte verrouillée chacune, ≥ 2 gardes.
- Extraction : héliport (NO) et/ou ponton (SE), bloc 2×2 de neige le plus proche du centre de la zone.
- Sous-sol « laboratoires enfouis » : non livré dans cette passe (`floors_min = 0`).

## Pré-rendu
```
flock /home/claude/.blender_render.lock tools/prerender/fl_pipeline.sh 12345 /tmp/fl12345        # 72 px/case (~1 h)
tools/prerender/fl_pipeline.sh 12345 /tmp/fl12345 12 4                                           # aperçu
```
Variables : `FL_EXPOSURE` (-0.5), `FL_SUN` (4.0), `FL_SKY` (0.32), `FL_ICELIGHT`, `FL_LIGHT`, `FL_SAT`,
`FL_CON`, `FL_LIFT`, `FL_BLOOM`, `FL_TILT`. Les objets `walls_<id>` / `front_<id>` / `roof_<id>` suivent
la convention des autres biomes (compose.py, occultation, intérieurs sans toit).

## Changements partagés (minimaux, additifs)
- `scripts/biomes/biome_registry.gd` : entrée `frozen_lands` dans `BIOMES`, builder dans `DEF_SCRIPTS`.
- `data/balance.cfg` : section `[frozen_lands]` ajoutée en fin de fichier ; `[maps] only_ids` :
  `"perm_terres_gelees"` ajouté une fois le paquet 72 px/case livré.
- `assets/ui/maps/build_map_thumbs.py` : fonction `frozen_lands()` (recadrage de la mini-carte du
  paquet, sinon illustration peinte) appelée dans `__main__`.
- `export_layout.gd`, `prerender_backdrop.gd` : aucun changement nécessaire (contrat générique suffisant).

## Évaluation (captures dans scratchpad/shots/frozen/)
| Itération | Changements | Note /10 |
|---|---|---|
| 1 | première scène complète | 4.7 (tout blanc, sans ombres) |
| 2 | exposition, soleil, béton sombre, navire plus haut | 5.5 |
| 3 | cristaux moins cramés, lumières de salles, sols plus sombres | 6.0 |
| 4 | falaises plus hautes, congères, lumières chaudes, H orange, blocs de glace au bord, toits détaillés | 6.5 |
| 5 | plan : base agrandie (remplit le plateau), galeries couvertes, fouillis de cour, barils rouges | 6.9 |
| 6 | exposition relevée, cristaux plus gros/bleus, 2e couronne de cristaux, trappe des hangars, fenêtres chaudes | 7.0 |
| 7 | îlots de mobilier dans les salles, lampadaires chauds de la cour, sols intérieurs sombres | 7.4 |
| 8 | navire ×1,25 (coque noire à bande rouge, cheminée rouge, mâts, canots), lampes d'alerte ×2, héliport sombre, falaises crénelées | 7.6 (jugé 6 par le chef de projet : plateau rond et vide, base dispersée) |
| 9 | **plan refait** : base compacte en croix, plateau = emprise dilatée à bord anguleux, 4 postes de garde reliés par des galeries couvertes, pont d'accès sur l'eau, labo R 10,5, projecteurs sur les toits | 7.6 |
| 10 | anneau du labo plus haut (1,6) avec hublots, voûtes nervurées des hangars, calottes de neige et lampes de parapet des tours | 7.5 (neige des hangars en dômes) |
| 11–12 | neige des hangars en bandes sur les nervures, congère plate au nord des toits de bunker | 7.7 |
| 13 | galeries traversant les blocs jusqu'à la passerelle (base enfin d'un seul tenant), postes de garde hors de l'anneau, escaliers des galeries sur le tronçon extérieur, marge de neige à bord anguleux (dilatation 9), îlots de neige isolés supprimés avant les portes | **7.7** |

Critères (itération 13) : volume/angle 7,5 · plan en croix 8,5 · labo central 8 · bunkers/dômes/héliport 7,5 ·
intérieurs 7,5 · navire/épave 7,5 · eau/banquise 8 · palette/lumières 7,5 · matières 7 · lisibilité en jeu 8.
Exigence : ≥ 7,5 avant le rendu final 72 px/case (rapport au chef de projet avant relance).

## Ce qui manque
- Sous-sol « laboratoires enfouis » (2D) ; bestiaire propre (phase 2) ; mobilier par gabarits
  (furnisher) comme la station ; crevasses plus lisibles ; tempête/neige animée en jeu limitée aux
  flocons du constructeur.
