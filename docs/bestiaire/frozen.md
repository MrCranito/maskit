# Bestiaire — Les Terres gelées (« Le désert de glace »)

Agent Terres gelées, branche `feature/bestiaire-mondes-4-6`. Référence : colonne du milieu de
`docs/reference/bestiaire_mondes_4_6.png`. Contrat : `CONTRAT.md` + `CONTRAT_MONDES_4_6.md`.
Le monde n'a pas encore de carte : pas de WorldData, de carte ni de générateur. Le bestiaire est décrit
dans `data/bestiary/frozen.tres` (`BestiaryData`), prêt à être recopié dans le WorldData du monde.

## Pipeline Blender
`art/blender/bestiary/frozen/build_frozen_bestiary.py` (autonome ; même caméra orthographique 3/4 à 48°,
même échelle monde 0,577 unité/px, même contour Freestyle et matériaux toon peints que le héros, via
`art/blender/rdm_common.py`). Le rig humanoïde, le rig araignée et l'infrastructure de rendu / atlas /
SpriteFrames sont **copiés** du bestiaire du centre commercial (aucun import croisé entre mondes).
Lumière froide bleutée (`C.WARM` = 0,94 / 1,00 / 1,10) ; glace bleue (reflets presque blancs, ombres bleu
nuit) ; lumières cyan émissives avec point chaud blanc (yeux, cœurs, cristaux, réservoirs cryo).

| Rig | Kinds |
|---|---|
| `Quad` (torse, cou + tête + mâchoire, 4 pattes à 3 segments, queue ; repris du Far West) + fourrure hirsute (`shaggy` : mèches sur le dos, collerette, joues) | Loup des glaces (bleu acier, crête de glace hérissée, grandes oreilles, gueule rouge ouverte, yeux ambre), Ours des neiges muté (variante lourde gris-brun : bosse d'épaules, grandes entailles rouges, gueule rouge et crocs, se dresse pour frapper) |
| `PolarSpider` (rig `Spider` sans tête d'araignée : grosse tête de loup blanc hirsute à gueule rouge et yeux rouges, thorax mécanique en segments, longues pattes d'acier épaisses, lueur rouge ventrale) | Araignée polaire |
| `Drone` (corps vertical acier sombre : dôme-tête à visière, grand œil cyan au torse, 2 grandes pinces en croissant, 6 pattes pendantes, queue effilée ; éclat de tir sur l'image 3 de l'attaque, œil éteint en mourant) | Drone de froid |
| `Human` + `SlamMixin` (frappe à deux poings ; bras longs, posture de gorille) : `Elemental` (glace taillée à facettes, éclats sur tout le corps, amas de cristaux aux épaules, griffes de glace, cœur cyan), `Titan` (même base en bleu profond, couronne de grandes flèches, visage lumineux, veines d'énergie) | Élémentaire, Titan |
| `Human` + `GunMixin` (arme à deux mains) : `Hunter` (armure grise givrée massive, capuche-casque, cagoule, grosses lunettes rondes orange, lourd fusil cryo tenu en travers) | Chasseur arctique |
| `Armored` (plaques, visière / cœur) : `Guardian` (+ `SlamMixin` : énormes épaulières facettées en couches, tête portée entre les épaules, visière en V cyan, gantelets, voyants), `Mechanic` (+ `GunMixin` : armure bleu acier, plastron et ceinture en laiton, grand œil cyclope cyan cerclé de laiton, canon-outil, clé, réservoirs) | élites |

Refonte des modèles (branche `feature/refonte-bestiaires`) : chaque modèle a été comparé à son illustration de la
planche (rendu 3/4 sud et sud-est agrandi) et refait jusqu'à une ressemblance jugée ≥ 7,5/10 (silhouette,
palette, matières, accessoires, posture, lisibilité). Comparaisons : `docs/bestiaire/captures/frozen/compare_*.png`.

```
source tools/prerender/mac_env.sh && flock "$BLENDER_LOCK" python3 art/blender/bestiary/frozen/build_frozen_bestiary.py [--kinds ice_wolf,...]
... --preview s,se --anim idle:0,attack:3 --kinds ice_bear     # aperçu rapide (RDM_TMP)
... --repack --kinds ice_wolf                                  # atlas + méta depuis les images rendues
... --sheet                                                    # planche de présentation (captures)
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup/tir, 4-5 retour),
hit (3), death (8, dernière image = cadavre) × 8 directions. Cadres (même densité de pixels) : 192 px
(drone, chasseur), 224 px (loup, araignée), 256 px (ours, élémentaire, mécanicien), 288 px (gardien).
Titan : rendu 384 px stocké à 72 % (`out_scale`, `world_per_px` compensé dans la méta) avec idle 4 /
run 6 / death 6 images, pour garder l'atlas mobile (< 8192 px).

## Monstres communs (rangée 1 = plus simples, rangée 2 = plus durs)

| Rangée | Kind | Nom | PV | Vitesse | Détection (vue / ouïe) | Attaque | Compétences |
|---|---|---|---|---|---|---|---|
| 1 | `ice_wolf` | Loup des glaces | 46 | 228 (rapide) | 420 px, 200° / 480 px | ruée + 2 morsures (8) | `ice_pack_hunter` (+12 % dégâts, +5 % vitesse par loup proche, max 3), `whistle` (hurlement : 1 loup, 2 vivants max), `ice_chill` |
| 1 | `ice_spider` | Araignée polaire | 64 | 200 | 260 px, 140° / **560 px** | ruée (10) | `ice_burrow` (enfouie hors combat : opacité 0,14, barre de vie cachée), `ice_ambush` (bond, 13 dans 60 px + immobilisée 0,7 s ; surprise : ×1,6 et télégraphe ×0,5), `ice_chill` |
| 1 | `ice_drone` | Drone de froid | 70 | 150 | 560 px, **360°** / 360 px, prévient à 620 px | rafale de 3 traits cyan (5), garde ses distances | `ice_storm` (1 tempête : ralenti 35 %, 3 dégâts/s, vision réduite), `ice_lab_call` (1 loup / chasseur, 2 max) |
| 2 | `ice_bear` | Ours des neiges muté | 320 | 96 (lent) | 380 px / 420 px | frappe de zone 95 px (20) | `charge` (20, renverse), `rage` (< 50 % : vitesse ×1,35), `ice_chill` (ralenti 35 %) |
| 2 | `ice_elemental` | Élémentaire de glace | 230 | 118 (moyenne) | 400 px / 380 px | frappe de zone 110 px (18) | `ice_frost_nova` (onde 260 px, 12 + ralenti 40 %), `ice_reform` (une fois : bloc de glace invulnérable 2,2 s puis 40 % des PV), `ice_chill` |
| 2 | `ice_hunter` | Chasseur arctique | 120 | 192 (rapide) | 520 px, 150° / 400 px | rafale de 3 (7), à couvert, contourne | `ice_cryo_shot` (couloir de visée puis trait cryo 12 + ralenti 50 % 2 s), `dodge_roll`, `ice_lab_call` (équipe : 1 chasseur sous 60 % PV) |

Comportements communs de la planche :
- **utilisent le froid et les tempêtes** : chaque commun gèle (coup gelé `ice_chill`, tempête, nova, tir
  cryo) ; tous les gels passent par le statut joueur existant « slow » (et « root » pour les pièges de glace) ;
- **se regroupent en patrouilles** : rayons d'alerte des voisins larges (300-620 px), meute de loups ;
  `[bestiary_frozen] group_chance` / `group_size` préparés pour le futur populator (comme `[bestiary_mall]`) ;
- **appellent des renforts des laboratoires** : `ice_lab_call` (drone, chasseur, mécanicien, Titan).

## Élites (`elite = true`, `BestiaryData.elite_kinds`)

| Kind | Nom | PV | Vitesse | Attaque | Compétences |
|---|---|---|---|---|---|
| `ice_glacier_guardian` | Gardien des glaces (tank / zone) — protège les accès aux installations souterraines | 640 | 88 | frappe de zone 120 px (26) ; phase 2 sous 50 % (vitesse ×1,2, recharges ×0,75) | `hard_skin` (armure de glace : −35 % de face), `ice_spikes` (ligne de pics, 18 + immobilisé 0,9 s), `ice_frost_nova` (300 px, 16, renverse 0,5 s, ralentit), `charge` |
| `ice_eternal_mechanic` | Mécanicien de l'Éternité (soutien) — répare et renforce les machines de la base | 460 | 110 | rafales de 4 traits (9), à couvert ; phase 2 sous 50 % | `ice_repair` (alliés dans 360 px : +30 % PV, +25 % dégâts 6 s ; lui : +12 %), `deploy_turret` (tourelle 14 s), `ice_lab_call` (2 drones, 3 max), `ice_cryo_shot` (3 traits en éventail) |

## Boss : `ice_titan` — Le Titan de glace, « Colosse né du noyau arctique »
4200 PV (le plus résistant des boss actuels), frappe de zone 160 px (30), aucun étourdissement ni recul,
détection 800 px / 360°, butin au sol garanti (`enemy_ice_titan`).

| Phase | PV | Compétences | Entrée | Multiplicateurs |
|---|---|---|---|---|
| 1 — Le colosse s'éveille | 100 → 70 % | `ice_spikes` (3 lignes de pics en éventail 40°), `ice_frost_nova` (320 px, ralentit), `shockwave` | — | — |
| 2 — Tempête de glace | 70 → 30 % | `ice_storm` (2 tempêtes, 3 vivantes, ralenti 45 %, 5 dégâts/s, 8 s), `ice_lab_call` « Les glaces s'éveillent » (3 renforts élémentaire / loups, 5 max), 5 lignes de pics, nova, onde de choc | tempête + renforts, invulnérable 1,5 s | vitesse ×1,1, recharges ×0,85, dégâts ×1,1 |
| 3 — Fureur du noyau (enragé) | 30 → 0 % | `ice_icefall` (8 stalactites autour du joueur, la 1re sur lui : 22 + ralenti 50 %), tempêtes (4 vivantes), renforts (élémentaire / chasseur / loup, 6 max), 7 lignes de pics sur 120°, nova double qui renverse, onde de choc | stalactites + nova, invulnérable 2 s | vitesse ×1,3, recharges ×0,65, dégâts ×1,4 |

Toutes les compétences du froid appliquent `e.phase_damage_mult` (dégâts de phase du boss) en plus de la
difficulté. Arène, règle « un seul boss par raid », barre de boss : chef de projet.

## Compétences propres (`scripts/enemies/skills/frozen/`, déclarées dans `registry.gd`)
| Id | Script | Effet |
|---|---|---|
| `ice_pack_hunter` | `ice_pack_hunter_skill.gd` | passif : bonus de meute (dégâts / vitesse par congénère proche) |
| `ice_chill` | `ice_chill_skill.gd` | passif : à la fin du coup de base (`notify_attack_done`), un joueur encore à portée est ralenti |
| `ice_burrow` | `ice_burrow_skill.gd` | passif : enfouie sous la neige hors combat (opacité, barre cachée), surgit en combat ou touchée |
| `ice_ambush` | `ice_ambush_skill.gd` | bond hors de la neige ; bonus de surprise si enfouie ou sortie depuis < 1,5 s |
| `ice_storm` | `ice_storm_skill.gd` + nœud `ice_storm.gd` | tempête de neige dérivante : ralenti, dégâts/s, vision réduite |
| `ice_frost_nova` | `ice_frost_nova_skill.gd` | anneau puis onde de froid (danger `shockwave`) + ralenti ; ondes multiples |
| `ice_reform` | `ice_reform_skill.gd` | passif : survit une fois au coup fatal, bloc de glace invulnérable, se reforme |
| `ice_cryo_shot` | `ice_cryo_shot_skill.gd` + nœud `ice_bolt.gd` | couloir de visée puis trait(s) cryogénique(s) (ralenti, immobilisation facultative), arrêtés par les murs |
| `ice_lab_call` | `ice_lab_call_skill.gd` (hérite de `whistle_skill.gd`) | message, alerte, renforts par la porte la plus proche |
| `ice_spikes` | `ice_spikes_skill.gd` + nœud `ice_shards.gd` | lignes de pics en cascade (couloirs + cercles), immobilisent ; s'arrêtent aux murs |
| `ice_icefall` | `ice_icefall_skill.gd` + nœud `ice_shards.gd` | pluie de stalactites (cercles puis impacts), ralentit |
| `ice_repair` | `ice_repair_skill.gd` | soin + renfort de dégâts temporaire des alliés proches |
Compétences communes réutilisées : `whistle`, `charge`, `rage`, `dodge_roll`, `hard_skin`, `shockwave`,
`deploy_turret`. Valeurs par défaut : `data/balance.cfg` `[bestiary_frozen]` ; chaque `.tres` les précise.

## Roster (`data/bestiary/frozen.tres`)
- Rangée 1 (loup, araignée, drone) : partout (araignée surtout en piège / fouille / couloirs, absente du
  repos et du départ) ; loups et drones au départ et au repos.
- Rangée 2 (ours, élémentaire, chasseur) : combat, extraction, super_loot, piège ; jamais au départ ni au repos.
  `[bestiary_frozen] row2_kinds` / `row2_floor_mult` prêts pour `populator.gd::_depth_roster()`.
- Escorte du boss (salle `boss`) : loups, drones, chasseurs.
- `elite_kinds = [ice_glacier_guardian, ice_eternal_mechanic]`, `boss_kind = ice_titan`.

## Butin
`data/loot_tables/enemy_ice_beast` (loup, araignée, ours), `enemy_ice_machine` (drone),
`enemy_ice_elemental`, `enemy_ice_hunter`, `enemy_ice_guardian`, `enemy_ice_mechanic`, `enemy_ice_titan`
(objets génériques existants : matériaux, soins, munitions, diamant brut, lingot, quelques armes ;
aucun objet propre au monde n'existe encore).

## Changements partagés
- `data/balance.cfg` : nouvelle section `[bestiary_frozen]` (additive, en fin de fichier avant `[bestiary_egypt]`).
- Aucun autre fichier partagé modifié.
- Points d'attention pour le chef de projet (coop) : les nœuds `ice_storm.gd`, `ice_bolt.gd`,
  `ice_shards.gd` sont créés par l'hôte et **non relayés** à l'invité (même limite que la tornade du
  Far West) ; l'opacité de l'araignée enfouie (`set_modulate`) n'est pas relayée non plus.

## Tests
`tests/test_bestiary_frozen.gd` : données, planches 8 directions, noms et caractéristiques de la planche,
compétences connues, comportements communs, roster du BestiaryData, effets (meute, morsure gelée,
araignée enfouie puis surprise, tempête, renforts, charge de l'ours, nova, reformation, tir cryo), élites
(pics, armure, réparation), boss (3 phases, tempête d'entrée, phase 3 enragée, stalactites).

## Captures (`docs/bestiaire/captures/frozen/`)
- `planche_modeles_frozen.png` — les 9 modèles (idle, attaque, cadavre).
- `en_jeu_classiques_repos.png`, `en_jeu_classiques_combat_0..3.png` — les 6 communs dans une arène de
  test sur Dust Creek (brouillard levé, HUD caché).
- `competences_telegraphes.png`, `competences_effets.png`, `competences_tempete.png` — tempête, nova,
  tir cryo, bond de l'araignée.
- `en_jeu_elites_repos.png`, `en_jeu_elites_combat_*.png`, `boss_*.png` — élites et boss.
Script de capture (xvfb) : copie de travail hors dépôt (scénarios classics / skills / elites / boss).
