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

## Passe « lumière et matières » (Mac M4, Blender 5.2 / Metal, 30/10/2026)
Objectif utilisateur : ≥ 9/10 de similitude, insistance sur le jeu de lumière et la profondeur des
textures. Aperçus ppc 12 / 4 échantillons (≈ 6 s par vue d'ensemble), gros plans `crop:` à 36-40 px/case.

| Itération | Changements | Note /10 |
|---|---|---|
| 14 | état repris (rendu du dépôt, plan iter. 13) | 6,3 (réévalué sévèrement : mer noire uniforme, falaise plate, murs clairs, pas de banquise) |
| 15–16 | matériaux refaits : neige (sastrugi, congères, paillettes, AO bleu), glace (strates, fissures Voronoï, coat, émission profonde), mer (turquoise près des côtes via attribut `shore`, écume, moutons) ; béton/toits sombres ; chapeaux de murs « acier givré » ; navire noir/gris | 6,6 |
| 17–22 | sol de neige maillé (3×3 facettes/case, congères gaussiennes, accumulation au pied des murs, lissé) ; falaise déplacée par bruit (surplomb), hauteurs continues ; terrasses de glace en Voronoï (lobes, 2 gradins) + pack de plaques + glaçons épars ; lampes suspendues ponctuelles (flaques chaudes), cristaux translucides (bleu profond, liseré cyan) ; héliport orange ; traces de chenilles, crevasses en zigzag, rochers | 6,7 |
| 23–30 | labo octogonal (mur en acier sombre, écrans cyan intérieurs, fosses techniques à la place des cases d'eau enclavées) ; hangars à charpente ouverte ; structures sur le plateau (avant-postes, citernes, conteneurs, radômes : `fl_outpost`, `fl_fuel_tanks`, `fl_containers`, `fl_radar`, collisions par emprise) ; balisage rouge du bord ; pont d'accès à garde-corps et feux rouges | 6,8 |
| 31–42 | étalonnage (exposition 0,4, virage des ombres, clarté), appliques chaudes de la passerelle, verrières éclairées sur les toits, îlots de mobilier par rôle (lits, tables, paillasses), débris épars, sols de cour/hangar enneigés par plaques | 6,9 |
| 43–49 | collisions : palettes sous les petits objets du fouillis (masque cohérent avec le plan), anneau de connexité renforcé ; murs ouverts plus hauts (1,75) + cornières d'arête claires | 7,0 |
| 50 | bord du plateau en anses profondes (`plat_coves`) ; pas de neige au-delà de BRIDGE_Y0 + 3 (le pont reste sur l'eau) | 7,0 (plafond : 3 itérations < +0,15) |
| final | 72 px/case, 16 échantillons, Metal : full 287 s, int 65 s, pipeline complet ≈ 7 min | **6,9–7,0** |

Critères (final, sévère) : plan/composition 6,5 · éléments signature 7,5 · intérieurs 7 · extérieurs/abords 7 ·
palette 7,5 · lumière 6,5 · profondeur/matières 6,5 · volume/angle 6 · lisibilité en jeu 8 · vignettes 6,5.
Ce qui bloque sous 9 : la planche est une peinture IA en perspective forte (bâtiments hauts, foisonnement de
petites pièces cloisonnées, halos et brume peints) alors que le jeu impose une caméra orthographique à 38° et
un plan en grandes salles ; la base reste un rectangle plein (bras de la croix trop larges, plateau
rectangulaire) ; les murs restent bas pour garder les intérieurs lisibles ; pas de brume/volumétrie (coût et
lisibilité des tuiles). Pistes : plan en croix aux bras étroits + cloisons intérieures, falaises plus hautes
en gradins sculptés, halos volumétriques ciblés autour des cristaux et projecteurs.

Réglages par défaut de `fl_scene.py` : `FL_EXPOSURE` 0,4 · `FL_SUN` 2,6 · `FL_SKY` 0,32 · `FL_SAT` 0,95 ·
`FL_CON` 1,32 · `FL_TONE` 0,3 (virage des ombres) · `FL_CLARITY` 35 · `FL_BLOOM` 0,7 / `FL_BLOOM_T` 185 ·
`FL_CRYSTAL` 1,6 · `FL_POOL` 2,2 (lampes suspendues) · `FL_SNOW_AO` 0,8 · `FL_DEBRIS` 0,07.
Nouveaux réglages de `[frozen_lands]` : `plat_coves` (amplitude des anses du plateau),
`outdoor_structures_area` (une structure de plateau pour N cases de neige). Monde : 4 décors ajoutés à
`prop_kinds` (rosters / élites / boss inchangés). Test : l'empreinte des grands décors peut être sur la
neige (STREET) en plus du sol (FLOOR).

## Ce qui manque
- Sous-sol « laboratoires enfouis » (2D) ; bestiaire propre (phase 2) ; mobilier par gabarits
  (furnisher) comme la station ; crevasses plus lisibles ; tempête/neige animée en jeu limitée aux
  flocons du constructeur.
