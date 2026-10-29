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
| `fw_bosses.py` | Le Buffle (quadrupède cuirassé, cornes, coup de corne) et Le Shérif Sable-Fou (cape, bras-canon, revolver + cheval monté pour l'animation `charge`) ; Le Déserteur est dans `fw_humans.py` |
| `build_fw_bestiary.py` | CLI : `--kinds`, `--preview s,se --anim idle:0,attack:3`, `--board <png>` |

```
flock /home/claude/.blender_render.lock python3 art/blender/bestiary/far_west/build_fw_bestiary.py [--kinds fw_bandit,...]
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup/tir, 4-5 retour),
hit (3), death (8, dernière image = cadavre) × 8 directions ; le shérif a en plus `charge` (8, à cheval,
jouée par `EnemyVisual.set_run_anim("charge")` pendant `fw_sheriff_charge`). Cadres : 192 px (humains),
224 px (hyène, chien), 288 px (Buffle), 320 px (Shérif à cheval) — même densité de pixels partout (la
caméra s'élargit avec le cadre).

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

## Élites et boss

| Kind | Nom | PV | Vitesse | Attaque | Compétences |
|---|---|---|---|---|---|
| `fw_deserter` | Le Déserteur (élite, bandit d'élite) | 380 | 150 | rafale de 5 (7 dmg), portée 440 | `dodge_roll` réactive (esquive rapide, 75 %), `whistle` (2 renforts bandit/pillard/tireur), `rage` sous 30 % ; phase 2 d'élite sous 50 % |
| `fw_buffalo` | Le Buffle (élite, bête colossale) | 650 | 95 | coup de corne de zone (26 dmg, rayon 110) | `charge` dévastatrice (720 px/s, 34 dmg, renverse), `fw_debris_throw` (éventail de 5 débris), `hard_skin` (cuirasse −30 % de face) ; phase 2 d'élite sous 40 % |
| `fw_sheriff` | **Le Shérif Sable-Fou** — « Maître des terres arides » (boss) | 3000 | 125 | revolver + canon : rafale de 2 (12 dmg), portée 480 | voir phases |

`WorldData` : `boss_kind = fw_sheriff`, `elite_kinds = [fw_deserter, fw_buffalo]`.

### Phases du Shérif (`phases`, format de `enemy_data.gd`)
| Phase | PV | Compétences | Modificateurs |
|---|---|---|---|
| 1 « Le hors-la-loi » | 100 → 70 % | `fw_revolver_shot` (tir précis 26 dmg, ligne de visée), `fw_call_outlaws` (2 renforts, 4 vivants max) | — |
| 2 « Tempête de sable » | 70 → 30 % | + `fw_sand_tornado` (lancée en entrant), `fw_sheriff_charge` (à cheval, 32 dmg, renverse) | vitesse ×1,1, invulnérable 1,5 s |
| 3 « Double tir » | 30 → 0 % | `fw_double_shot` (2 balles à la fois, recharge 1,8 s), revolver, renforts ×3 (6 vivants, Déserteur possible, lancés en entrant), tornades ×2, charge | vitesse ×1,2, recharges ×0,7, dégâts ×1,15, invulnérable 2 s |

Compétences ajoutées au registre Far West : `fw_debris_throw`, `fw_revolver_shot`, `fw_double_shot`
(classe commune `projectile_skill.gd`), `fw_call_outlaws` (classe commune `whistle_skill.gd`),
`fw_sand_tornado` (`sand_tornado_skill.gd` + nœud `sand_tornado.gd` : nuage tourbillonnant au-dessus des
personnages qui dérive vers le joueur — vision réduite, statut « slow » −45 %, 4 dégâts/s),
`fw_sheriff_charge` (`sheriff_charge_skill.gd`, hérite de la charge commune, animation à cheval).
L'arène (« Ville abandonnée — Fort du shérif ») et la règle d'un seul boss par raid sont gérées par le
chef de projet.

## Roster (`data/worlds/world_01_far_west.tres`)
- Rangée 1 (bandit, pillard, tireur) : partout (le bandit dans toutes les salles).
- Rangée 2 (maraudeur, robuste, chien) : surtout combat / extraction / salle au trésor / boss ;
  rares dans les salles de fouille, absents du repos.
- Étages profonds : `[bestiary_far_west] row2_kinds` + `row2_floor_mult` (×1,6 au sous-sol, ×0,7 au
  rez-de-chaussée, ×1,3 à l'étage), appliqué par `populator.gd` (voir Changements partagés).

## Butin
Tables `data/loot_tables/enemy_fw_*.tres` (reprises des anciennes tables équivalentes ; bêtes :
peu de butin, `mat_cloth`, pièces avalées). `corpse_name` dans chaque `.tres`.
Élites et boss : `enemy_fw_deserter` (reprise de l'ancien chef de bande), `enemy_fw_buffalo`,
`enemy_fw_sheriff` (4 à 6 tirages, étoile de shérif, sacs d'or, rares armes) ; butin au sol garanti.

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

## Captures (`docs/bestiaire/captures/far_west/`)
- `modeles.png` : planche de présentation des 9 modèles (idle, course, attaque, cadavre ; + charge à cheval).
- `classiques_en_jeu.png`, `combat_0..3.png`, `meute_0..2.png` : classiques en jeu (raid réel).
- `elites_boss_en_jeu.png`, `boss_phase1.png`, `boss_charge_telegraphe.png`, `boss_tornade.png`, `boss_phase3.png` : élites et boss.
- `docs/bestiaire/captures/.gdignore` : Godot n'importe pas les captures.
Script de capture (xvfb) : copie de travail hors dépôt ; scénarios lineup / fight / pack / elites / boss.

## Changements partagés
- `scripts/dungeon/gen/populator.gd` : ajout générique `_depth_roster()` (poids des kinds
  `row2_kinds` × `row2_floor_mult` de `[bestiary_<biome>]`, inchangé sans section) appelé dans
  `_enemies()` à la place de `c.world.get_roster(room.type)` seul.
- `scripts/enemies/enemy_visual.gd` : (1) suppression des entrées SVG de repli des anciens kinds Far
  West dans `KINDS` (SVG supprimés) ; (2) ajout `set_run_anim(an)` + variable `_run_anim` (animation
  de course de remplacement, ex. « charge » à cheval ; remise à "run" dans `_reset_effects`).
- `scripts/net/net_protocol.gd` : `FX_METHODS` += `&"set_run_anim"` (en fin de liste, relais coop).
- `scripts/player/player_status.gd` : nouveau statut `&"slow"` + `speed_mult()` ;
  `scripts/player/player.gd` `get_effective_speed()` × `status.speed_mult()`.
- `art/blender/build_enemies.py` : `ARCH` vidé (anciens hors-la-loi) ; le module reste la bibliothèque
  commune (la Station l'importe).
- `data/balance.cfg` : `[enemy_variants]` sans les variantes outlaw_knife / gunslinger ; nouvelle
  section `[bestiary_far_west]`.
- À reprendre par le chef de projet : `whistle_skill.gd` a encore `kinds` par défaut
  `["outlaw_knife", "gunslinger"]` (sans effet pour le Far West : tous les `.tres` précisent `kinds`).
