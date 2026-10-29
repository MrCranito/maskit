# Bestiaire — Far West (« Les bandits du désert »)

Refonte d'après `docs/reference/bestiaire_classique.png` (colonne FAR WEST) et
`docs/reference/bestiaire_elites_boss.png` (colonne FAR WEST). Agent Far West, branche
`feature/bestiaire`.

## Pipeline Blender
`art/blender/bestiary/far_west/` (autonome, même caméra 3/4 à 48°, même échelle, même contour
Freestyle et mêmes matériaux toon peints que le héros et l'ancien `art/blender/build_enemies.py`) :

| Fichier | Rôle |
|---|---|
| `fw_sheet.py` | rendu 8 directions, atlas rogné, SpriteFrames + méta (format `EnemyArt`) |
| `fw_humans.py` | humanoïdes (rig à joints + IK des bras) : Bandit, Pillard, Tireur d'élite, Robuste |
| `fw_beasts.py` | quadrupèdes (rig propre : torse, cou/tête/mâchoire, 4 pattes à 3 segments, queue) : Maraudeur, Chien de garde |
| `build_fw_bestiary.py` | CLI : `--kinds`, `--preview s,se --anim idle:0,attack:3`, `--board <png>` |

```
flock /home/claude/.blender_render.lock python3 art/blender/bestiary/far_west/build_fw_bestiary.py [--kinds fw_bandit,...]
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup/tir, 4-5 retour),
hit (3), death (8, dernière image = cadavre) × 8 directions. Cadre 192 px (humains), 224 px (bêtes,
même densité de pixels : la caméra s'élargit avec le cadre).

## Monstres classiques (rangée 1 = plus simples, rangée 2 = plus durs)

| Kind | Nom | PV | Vitesse | Détection (vue / ouïe) | Attaque | Tactique | Compétences |
|---|---|---|---|---|---|---|---|
| `fw_bandit` | Bandit | 42 | 135 | 440 px, 160° / 380 px | fusil, rafale de 2 (8 dmg), portée 400 | gunner, couvert, contourne | `cover_roll`, `whistle` (1 renfort bandit/pillard, PV < 70 %) |
| `fw_raider` | Pillard | 70 | 200 | 360 px / 420 px, seuil d'alerte 0,8 | hache, ruée (15 dmg) | rusher, zigzag | `rush` (charge dès qu'il repère, renverse) |
| `fw_sharpshooter` | Tireur d'élite | 36 | 100 | 640 px, 110° | tir visé longue portée (22 dmg, portée 680, ligne de visée) | sniper, couvert | `relocate` (change de couvert après chaque tir), `piercing` |
| `fw_marauder` | Maraudeur (hyène) | 62 | 250 | 400 px, 220° / 460 px | morsure, ruée + 2 coups (9 dmg) | rusher, zigzag, contourne | `fw_pack_hunter` (+15 % dégâts, +6 % vitesse par congénère, max 3), `fw_pack_howl` (rameute la meute, 1 renfort si seul), `dodge_roll` |
| `fw_bruiser` | Robuste | 240 | 78 | 320 px | masse, coup de zone (22 dmg, rayon 85) | heavy | `hard_skin` (bouclier : −60 % de face), `fw_bodyguard` (se place entre le joueur et l'allié le plus blessé), `charge` (coup de bouclier) |
| `fw_guard_dog` | Chien de garde | 30 | 240 | 520 px, 300° / 620 px (meilleure ouïe) | morsure (6 dmg, rapide) | rusher | `fw_alarm_bark` (alerte tous les ennemis à 760 px, débusque un joueur caché tout près) |

Comportements communs de la planche : encerclement (`can_flank`), couverture (`use_cover` des
tireurs), renforts (sifflet du bandit, hurlement du maraudeur, aboiement du chien).

### Compétences propres (`scripts/enemies/skills/far_west/`, déclarées dans `registry.gd`)
- `fw_alarm_bark` (`alarm_bark_skill.gd`) — aboiement : tous les ennemis dans `radius` deviennent alertés sur la position du joueur.
- `fw_pack_hunter` (`pack_hunter_skill.gd`, passif) — bonus de dégâts/vitesse par congénère proche (multiplicateurs de l'ennemi, recalcul toutes les 0,5 s).
- `fw_pack_howl` (`pack_howl_skill.gd`, hérite du sifflet commun) — rameute la meute ; si moins de `min_pack` congénères proches, un maraudeur surgit.
- `fw_bodyguard` (`bodyguard_skill.gd`) — garde du corps du Robuste.
Valeurs par défaut : `data/balance.cfg` `[bestiary_far_west]` ; chaque `.tres` les précise.

## Roster (`data/worlds/world_01_far_west.tres`)
- Rangée 1 (bandit, pillard, tireur) : partout (le bandit dans toutes les salles).
- Rangée 2 (maraudeur, robuste, chien) : surtout combat / extraction / salle au trésor / boss ;
  rares dans les salles de fouille, absents du repos.
- Étages profonds : `[bestiary_far_west] row2_kinds` + `row2_floor_mult` (×1,6 au sous-sol, ×0,7 au
  rez-de-chaussée, ×1,3 à l'étage), appliqué par `populator.gd` (voir Changements partagés).

## Butin
Tables `data/loot_tables/enemy_fw_*.tres` (reprises des anciennes tables équivalentes ; bêtes :
peu de butin, `mat_cloth`, pièces avalées). `corpse_name` dans chaque `.tres`.

## Correspondance anciens kinds → nouveaux (pour `data/weapons/*.tres` `unlock_enemy_kind`)
| Ancien kind | Arme débloquée | Nouveau kind proposé |
|---|---|---|
| `gunslinger` | `pistol_deagle` (5 kills) | `fw_bandit` |
| `shotgun_brute` | `rifle_scarh` (3 kills) | `fw_bruiser` |
| `rifleman` | `sniper_m82` (1 kill) | `fw_sharpshooter` |
| `dynamiter` | `rocket_rpg7` (3 kills) | `fw_raider` |
| `gang_boss` | `rocket_m202` (1 kill) | `fw_deserter` (élite) |
| `outlaw_knife` | — | `fw_raider` |
| `sandstone_colossus` (boss) | — | `fw_sheriff` (boss) |
(`tools/gen_weapons.py` lignes 136-141 et `tests/test_economy.gd` utilisent aussi ces kinds.)

## Changements partagés
- `scripts/dungeon/gen/populator.gd` : ajout générique `_depth_roster()` (poids des kinds
  `row2_kinds` × `row2_floor_mult` de `[bestiary_<biome>]`, inchangé sans section) appelé dans
  `_enemies()` à la place de `c.world.get_roster(room.type)` seul.
- `data/balance.cfg` : nouvelle section `[bestiary_far_west]` (fin du fichier).
