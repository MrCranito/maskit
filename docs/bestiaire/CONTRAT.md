# Refonte du bestiaire (branche `feature/bestiaire`)

Demande : supprimer tous les monstres actuels et les remplacer par ceux des planches
- `docs/reference/bestiaire_classique.png` : 6 monstres classiques par monde ;
  1re rangée = les plus simples, 2e rangée = plus durs (et de gauche à droite : de plus en plus durs) ;
- `docs/reference/bestiaire_elites_boss.png` : par monde, 1 boss (3 phases) et 2 élites.

Règles du jeu demandées :
- **un seul boss par monde et par raid**, vraiment très difficile à battre ;
- **2 élites par monde**.

## Organisation
- 1 agent par monde (Far West, Station spatiale, Centre commercial), dans la même copie de travail
  `/home/claude/maskit`, branche `feature/bestiaire`. **Les agents ne font pas de commit** : le chef
  de projet (agent principal) committe et ouvre la PR.
- Ordre pour chaque agent : 1) les 6 monstres classiques (modèles Blender + données + IA/compétences
  + roster), 2) ensuite seulement les 2 élites et le boss.
- Rendu Blender : 2 cœurs CPU pour 3 agents. **Tout rendu Blender passe par le verrou**
  `flock /home/claude/.blender_render.lock <commande>` (un seul rendu à la fois). Codez pendant que
  les autres rendent.
- Godot (compilation, tests) : `flock /home/claude/.godot.lock godot --headless ...` pour éviter que
  deux imports se marchent dessus.

## Fichiers : qui possède quoi
| Zone | Propriétaire |
|---|---|
| `data/enemies/fw_*.tres`, `assets/sprites/enemies/fw_*/`, `art/blender/bestiary/far_west/`, `scripts/enemies/skills/far_west/`, `data/worlds/world_01_far_west.tres`, `data/loot_tables/enemy_fw_*.tres`, `tests/test_bestiary_far_west.gd`, `docs/bestiaire/far_west.md`, section `[bestiary_far_west]` de balance.cfg | agent Far West |
| idem avec `ss_` / `space_station` / `world_02_space_station.tres` / `[bestiary_space_station]` | agent Station |
| idem avec `mall_` / `mall` / `world_03_mall.tres` / `[bestiary_mall]` | agent Centre commercial |
| tout le reste : `scripts/enemies/enemy.gd`, `enemy_visual.gd`, `enemy_data.gd`, `enemy_skills.gd`, `enemy_variants.gd`, populators, HUD (barre de boss), `world_data.gd`, tests génériques, armes (`unlock_enemy_kind`), économie, suppression des anciens monstres génériques (golem, masked_*, uw_*) | chef de projet |

Les anciens monstres d'un monde (Far West : outlaw_knife, gunslinger, shotgun_brute, rifleman,
dynamiter, gang_boss, sandstone_colossus ; Station : space_* ; Centre commercial : mall_*) sont
supprimés par l'agent du monde (données, sprites, scripts Blender, références dans son populator /
ses tests), une fois ses nouveaux monstres branchés dans le roster.

Besoin d'un changement dans un fichier partagé : faites-le **minimal, générique et additif**, avec
Edit sur les lignes précises (jamais de réécriture complète du fichier), et notez-le dans
`docs/bestiaire/<monde>.md` (section « Changements partagés »). Relisez le fichier juste avant.

## Contrat technique
- Identifiants : `fw_<nom>`, `ss_<nom>`, `mall_<nom>` (ex. `fw_bandit`, `ss_security_droid`,
  `mall_zombie`). Les élites et le boss suivent le même préfixe.
- Données : `data/enemies/<kind>.tres` (EnemyData). Aucune valeur d'équilibrage en dur dans le code :
  tout dans le .tres ou la section `[bestiary_<monde>]` de balance.cfg.
- Visuel : mode « planches » d'EnemyArt (8 directions × idle / run / attack / hit / death, la dernière
  image de death = cadavre), sorties dans `assets/sprites/enemies/<kind>/` (`<kind>_atlas.png`,
  `<kind>_frames.tres`, `<kind>_meta.json`). Pipeline de référence : `art/blender/build_enemies.py`
  (même caméra, échelle, contour, matériaux peints que le héros). Les créatures non humanoïdes
  (chien, hyène, araignées, drones, bouffle…) ont leur propre rig dans vos scripts.
- Compétences : `scripts/enemies/skills/<monde>/<nom>_skill.gd` (classe EnemySkill) déclarées dans
  `scripts/enemies/skills/<monde>/registry.gd` (`const REGISTRY := {&"id": "res://…/x_skill.gd"}`),
  ou réutilisez celles du registre commun (`EnemySkills.REGISTRY` : dodge_roll, knife_throw,
  fan_volley, charge, rush, shield, energy_shield, relocate, piercing, molotov, grenade,
  flash_grenade, whistle, rage, teleport, kamikaze, deploy_turret, shockwave).
- Roster : `enemy_roster` du `data/worlds/world_0X_*.tres` du monde ; 1re rangée de la planche dans
  toutes les salles, 2e rangée surtout dans les salles combat / extraction et aux étages profonds.
- **Élites** : `elite = true` dans le .tres + liste `elite_kinds` (2 ids) dans le WorldData. Le chef
  de projet les place : gardes des salles au trésor (super_loot), escorte du boss, rares ailleurs.
- **Boss** : `boss = true`, `boss_title`, `phases` (3 phases de la planche : from 1.0 / 0.7 / 0.3 ;
  format documenté dans `scripts/enemies/enemy_data.gd`, groupe « Boss »), `boss_kind` du WorldData.
  Le chef de projet garantit **un seul boss par raid**, la barre de boss, l'arène et la transition de
  phase. Le boss doit être **vraiment très difficile** : beaucoup de PV, compétences de la planche,
  renforts (élites / classiques de son monde), phase 3 enragée.
- Difficulté : les 6 classiques montent en difficulté (rangée 1 < rangée 2, gauche < droite).
- Tests GUT : `tests/test_bestiary_<monde>.gd` (chaque kind charge, a ses planches, est dans le
  roster ; élites / boss bien déclarés ; compétences connues). La suite complète doit rester verte.
- Captures pour la PR : `docs/bestiaire/captures/<monde>/` (planche de présentation des modèles +
  captures en jeu), le chef de projet les publie sur `pr-assets`.
