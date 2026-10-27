# Crédits et licences des assets tiers

Ce fichier recense tous les assets tiers intégrés au projet (sons, musiques, polices, icônes).
Chaque licence a été vérifiée à la source (fichier LICENSE du dépôt d'origine) le 27/10/2026.
Seules les licences CC0, CC-BY 3.0/4.0, SIL OFL 1.1 et MIT/zlib sont acceptées.

Le code du jeu reste sous la licence du dépôt (voir `LICENSE`).

---

## Attribution à afficher dans le jeu

À reprendre tel quel dans l'écran « Crédits » (obligatoire pour les icônes, qui sont sous CC-BY 3.0) :

> **Icônes** : Icons made by Lorc, Delapouite, Skoll, Sbed, Carl Olsen, John Colburn, Guard13007 and Willdabeast, from game-icons.net — licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Icons modified (background removed).
> **Polices** : « Rye » © 2011 Sorkin Type Co ; « Nunito » © 2014 The Nunito Project Authors — SIL Open Font License 1.1.
> **Sons et musiques** : Pixel-boy / Sparklin Labs (Superpowers Asset Packs, CC0) ; Kenney (www.kenney.nl, CC0).

(Les mentions des sons CC0 ne sont pas obligatoires, mais les auteurs l'apprécient.)

---

## 1. Superpowers Asset Packs — sons et musiques

- **Auteur** : Pixel-boy, pour Sparklin Labs (Superpowers HTML5)
- **URL** : https://github.com/sparklinlabs/superpowers-asset-packs
- **Licence** : CC0 1.0 (fichier `LICENSE.txt` du dépôt + README : « released under the Creative Commons Zero (CC0) license »)
- **Packs utilisés** : `western-fps-2d` (tirs, impacts, pas dans le sable, cris, ambiance désert, **musiques western**), `top-down-shooter`, `medieval-fantasy`, `ninja-adventure`
- **Musiques** (pack `western-fps-2d/musics`, boucles, import `loop=true`) :

| Fichier du jeu | Fichier d'origine | Durée | Taille |
|---|---|---|---|
| `assets/audio/music/western_hub.ogg` | `western-fps-2d/musics/theme-2.ogg` | 48 s | 0,95 Mo |
| `assets/audio/music/western_explore.ogg` | `western-fps-2d/musics/theme-1.ogg` | 72 s | 1,4 Mo |
| `assets/audio/music/western_combat.ogg` | `western-fps-2d/musics/theme-3.ogg` | 54 s | 1,05 Mo |

## 2. Kenney — Interface Sounds et UI Audio

- **Auteur** : Kenney Vleugels (www.kenney.nl)
- **URL** : https://github.com/Calinou/kenney-interface-sounds et https://github.com/Calinou/kenney-ui-audio (redistributions officielles en addon Godot par Hugo Locurcio / Calinou, listées sur l'Asset Library Godot)
- **Licence** : CC0 1.0 (fichier `LICENSE.txt` de Kenney inclus dans chaque dépôt : « License: (Creative Commons Zero, CC0) »)
- Fichiers .wav convertis en .ogg Vorbis (ffmpeg, qualité 4).

## 3. Kenney — Starter Kits Godot (sons)

- **Auteur** : Kenney (www.kenney.nl)
- **URL** : https://github.com/KenneyNL/Starter-Kit-FPS, https://github.com/KenneyNL/Starter-Kit-3D-Platformer, https://github.com/KenneyNL/Starter-Kit-Racing, https://github.com/KenneyNL/Starter-Kit-Match-3
- **Licence** : code sous MIT ; README de chaque kit : « Assets included in this package (2D sprites, 3D models and sound effects) are CC0 licensed ». Seuls des sons sont repris (aucun code).

## 4. Polices (SIL Open Font License 1.1)

| Police | Usage | Fichier | Auteur | Source |
|---|---|---|---|---|
| Rye | Titres style western | `assets/fonts/rye/Rye-Regular.ttf` | Sorkin Type Co (Nicole Fally) | https://github.com/google/fonts/tree/main/ofl/rye |
| Nunito (variable, graisses 200-1000) | Texte courant, lisible sur mobile | `assets/fonts/nunito/Nunito-Variable.ttf` | The Nunito Project Authors (Vernon Adams, Cyreal, Jacques Le Bailly) | https://github.com/google/fonts/tree/main/ofl/nunito |

Le texte de la licence est fourni dans chaque dossier (`OFL.txt`). Licence vérifiée dans `OFL.txt` et `METADATA.pb` (`license: "OFL"`) du dépôt google/fonts. Nom réservé : « Rye » (la police ne doit pas être renommée « Rye » si on la modifie).

## 5. Icônes — game-icons.net

- **Auteurs** : Lorc (35), Delapouite (31), Sbed (5), Skoll (4), Carl Olsen, John Colburn, Guard13007, Willdabeast, Zeromancer (CC0)
- **URL** : https://game-icons.net — dépôt https://github.com/game-icons/icons
- **Licence** : CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/), sauf Zeromancer en CC0 (`license.txt` du dépôt, copié dans `assets/third_party/icons/LICENSE.txt`). Mention exigée : « Icons made by {author} ».
- **Modification** : le carré de fond noir (`<path d="M0 0h512v512H0z"/>`) a été retiré. Les icônes sont des glyphes blancs sur fond transparent, à teinter via `modulate` (couleurs de rareté, etc.).
- 80 icônes dans `assets/third_party/icons/`.

---

## Table de correspondance — effets sonores

Tous les sons sont dans `assets/audio/sfx/`. Les noms logiques utilisés par `AudioManager.play_sfx()` sont le nom du fichier sans le suffixe `_N` (ex. `revolver_shot` → 3 variantes).

| Fichier du jeu | Source | Fichier d'origine |
|---|---|---|
| `sfx/weapons/revolver_shot_1.ogg` | Superpowers | `western-fps-2d/sounds/gun-1.ogg` |
| `sfx/weapons/revolver_shot_2.ogg` | Superpowers | `western-fps-2d/sounds/gun-2.ogg` |
| `sfx/weapons/revolver_shot_3.ogg` | Superpowers | `western-fps-2d/sounds/gun-3.ogg` |
| `sfx/weapons/rifle_shot.ogg` | Superpowers | `western-fps-2d/sounds/gun-4.ogg` |
| `sfx/weapons/pistol_shot_light.ogg` | Superpowers | `western-fps-2d/sounds/gun-5.ogg` |
| `sfx/weapons/shotgun_blast.ogg` | Superpowers | `top-down-shooter/sounds/shoot-1.wav` |
| `sfx/weapons/gun_shot_alt.ogg` | Superpowers | `top-down-shooter/sounds/shoot-2.wav` |
| `sfx/weapons/bow_shot.ogg` | Superpowers | `western-fps-2d/sounds/arrow.ogg` |
| `sfx/weapons/reload.ogg` | Superpowers | `western-fps-2d/sounds/reload.ogg` |
| `sfx/weapons/dry_fire.ogg` | Superpowers | `western-fps-2d/sounds/no-ammo.ogg` |
| `sfx/weapons/blade_swing_1.ogg` | Superpowers | `western-fps-2d/sounds/woosh-1.ogg` |
| `sfx/weapons/blade_swing_2.ogg` | Superpowers | `western-fps-2d/sounds/woosh-2.ogg` |
| `sfx/weapons/blade_swing_3.ogg` | Superpowers | `western-fps-2d/sounds/woosh-3.ogg` |
| `sfx/weapons/blade_swing_heavy.ogg` | Superpowers | `top-down-shooter/sounds/sword-2.wav` |
| `sfx/weapons/blade_clash.ogg` | Superpowers | `top-down-shooter/sounds/sword-1.wav` |
| `sfx/weapons/explosion_1.ogg` | Superpowers | `western-fps-2d/sounds/explosion-1.ogg` |
| `sfx/weapons/explosion_2.ogg` | Superpowers | `western-fps-2d/sounds/explosion-2.ogg` |
| `sfx/weapons/explosion_3.ogg` | Superpowers | `western-fps-2d/sounds/explosion-3.ogg` |
| `sfx/weapons/flame.ogg` | Superpowers | `top-down-shooter/sounds/flame-thrower.wav` |
| `sfx/weapons/weapon_switch.ogg` | Kenney Starter Kit FPS | `sounds/weapon_change.ogg` |
| `sfx/impacts/bullet_impact_1.ogg` | Superpowers | `western-fps-2d/sounds/impact-1.ogg` |
| `sfx/impacts/bullet_impact_2.ogg` | Superpowers | `western-fps-2d/sounds/impact-2.ogg` |
| `sfx/impacts/hit_flesh.ogg` | Kenney Starter Kit FPS | `sounds/enemy_hurt.ogg` |
| `sfx/impacts/hit_heavy.ogg` | Superpowers | `top-down-shooter/sounds/hit.wav` |
| `sfx/impacts/projectile_destroy.ogg` | Superpowers | `top-down-shooter/sounds/shoot-destroy.wav` |
| `sfx/impacts/metal_impact.ogg` | Kenney Starter Kit Racing | `audio/impact.ogg` |
| `sfx/impacts/wood_break.ogg` | Kenney Starter Kit 3D Platformer | `sounds/break.ogg` |
| `sfx/impacts/glass_break_1.ogg` | Superpowers | `western-fps-2d/sounds/glass-breaking-1.ogg` |
| `sfx/impacts/glass_break_2.ogg` | Superpowers | `western-fps-2d/sounds/glass-breaking-2.ogg` |
| `sfx/impacts/glass_hit.ogg` | Superpowers | `top-down-shooter/sounds/window-hit-2.wav` |
| `sfx/movement/step_sand.ogg` | Superpowers | `western-fps-2d/sounds/sand-step.ogg` |
| `sfx/movement/steps_loop.ogg` | Kenney Starter Kit 3D Platformer | `sounds/walking.ogg` |
| `sfx/movement/land.ogg` | Kenney Starter Kit 3D Platformer | `sounds/land.ogg` |
| `sfx/movement/dash.ogg` | Superpowers | `medieval-fantasy/sounds/woosh-2.wav` |
| `sfx/movement/jump.ogg` | Kenney Starter Kit FPS | `sounds/jump_a.ogg` |
| `sfx/doors/door_open.ogg` | Kenney Interface Sounds | `open_002.wav` |
| `sfx/doors/door_close.ogg` | Kenney Interface Sounds | `close_002.wav` |
| `sfx/doors/door_locked.ogg` | Kenney Interface Sounds | `error_006.wav` |
| `sfx/doors/door_unlock.ogg` | Kenney Interface Sounds | `switch_003.wav` |
| `sfx/loot/coin_pickup.ogg` | Kenney Starter Kit 3D Platformer | `sounds/coin.ogg` |
| `sfx/loot/gold_pickup.ogg` | Superpowers | `ninja-adventure/sounds/gold-1.ogg` |
| `sfx/loot/item_pickup.ogg` | Kenney Interface Sounds | `drop_002.wav` |
| `sfx/loot/ammo_pickup.ogg` | Superpowers | `western-fps-2d/sounds/ammo.ogg` |
| `sfx/loot/container_search_1.ogg` | Kenney Interface Sounds | `scratch_001.wav` |
| `sfx/loot/container_search_2.ogg` | Kenney Interface Sounds | `scratch_003.wav` |
| `sfx/loot/container_open.ogg` | Kenney Interface Sounds | `open_004.wav` |
| `sfx/loot/rare_reveal.ogg` | Superpowers | `ninja-adventure/sounds/secret-1.wav` |
| `sfx/loot/key_pickup.ogg` | Superpowers | `ninja-adventure/sounds/power-up-2.ogg` |
| `sfx/loot/item_equip.ogg` | Kenney Starter Kit Match-3 | `sounds/tile-swap.ogg` |
| `sfx/enemies/outlaw_death_1.ogg` | Superpowers | `western-fps-2d/sounds/scream-1.ogg` |
| `sfx/enemies/outlaw_death_2.ogg` | Superpowers | `western-fps-2d/sounds/scream-2.ogg` |
| `sfx/enemies/outlaw_death_3.ogg` | Superpowers | `western-fps-2d/sounds/scream-3.ogg` |
| `sfx/enemies/outlaw_hurt_1.ogg` | Superpowers | `western-fps-2d/sounds/scream-4.ogg` |
| `sfx/enemies/outlaw_hurt_2.ogg` | Superpowers | `western-fps-2d/sounds/scream-5.ogg` |
| `sfx/enemies/outlaw_hurt_3.ogg` | Superpowers | `western-fps-2d/sounds/scream-6.ogg` |
| `sfx/enemies/enemy_death_generic.ogg` | Superpowers | `top-down-shooter/sounds/death.wav` |
| `sfx/enemies/enemy_destroy.ogg` | Kenney Starter Kit FPS | `sounds/enemy_destroy.ogg` |
| `sfx/enemies/enemy_attack.ogg` | Kenney Starter Kit FPS | `sounds/enemy_attack.ogg` |
| `sfx/enemies/golem_growl_1.ogg` | Superpowers | `medieval-fantasy/sounds/monster-1.wav` |
| `sfx/enemies/golem_growl_2.ogg` | Superpowers | `medieval-fantasy/sounds/monster-2.wav` |
| `sfx/enemies/golem_stomp.ogg` | Superpowers | `top-down-shooter/sounds/explosion-3.wav` |
| `sfx/enemies/golem_crumble.ogg` | Superpowers | `top-down-shooter/sounds/explosion-2.wav` |
| `sfx/alerts/enemy_alert.ogg` | Superpowers | `top-down-shooter/sounds/alert.wav` |
| `sfx/alerts/danger_jingle.ogg` | Superpowers | `ninja-adventure/sounds/alert.ogg` |
| `sfx/player/player_hurt.ogg` | Superpowers | `top-down-shooter/sounds/window-hit-1.wav` |
| `sfx/player/player_death.ogg` | Superpowers | `ninja-adventure/sounds/game-over.ogg` |
| `sfx/player/heal.ogg` | Superpowers | `top-down-shooter/sounds/cure.wav` |
| `sfx/player/power_up.ogg` | Superpowers | `ninja-adventure/sounds/power-up.ogg` |
| `sfx/player/mask_power.ogg` | Superpowers | `ninja-adventure/sounds/magic-1.ogg` |
| `sfx/player/extraction_success.ogg` | Superpowers | `ninja-adventure/sounds/succes-2.ogg` |
| `sfx/player/extraction_fail.ogg` | Superpowers | `ninja-adventure/sounds/game-over-2.ogg` |
| `sfx/ui/click.ogg` | Kenney Interface Sounds | `click_001.wav` |
| `sfx/ui/click_soft.ogg` | Kenney UI Audio | `click3.wav` |
| `sfx/ui/hover.ogg` | Kenney Interface Sounds | `select_001.wav` |
| `sfx/ui/confirm.ogg` | Kenney Interface Sounds | `confirmation_001.wav` |
| `sfx/ui/confirm_big.ogg` | Kenney Interface Sounds | `confirmation_002.wav` |
| `sfx/ui/back.ogg` | Kenney Interface Sounds | `back_001.wav` |
| `sfx/ui/error.ogg` | Kenney Interface Sounds | `error_004.wav` |
| `sfx/ui/panel_open.ogg` | Kenney Interface Sounds | `maximize_001.wav` |
| `sfx/ui/panel_close.ogg` | Kenney Interface Sounds | `minimize_001.wav` |
| `sfx/ui/toggle.ogg` | Kenney Interface Sounds | `toggle_001.wav` |
| `sfx/ui/tick.ogg` | Kenney Interface Sounds | `tick_002.wav` |
| `sfx/ui/coin_spend.ogg` | Kenney Interface Sounds | `glass_001.wav` |
| `sfx/ambience/desert_wind.ogg` | Superpowers | `western-fps-2d/sounds/desert-ambience.ogg` |
| `sfx/ambience/raven.ogg` | Superpowers | `western-fps-2d/sounds/raven-2.ogg` |
| `sfx/ambience/cattle.ogg` | Superpowers | `western-fps-2d/sounds/bulls.ogg` |

## Table de correspondance — icônes

| Fichier du jeu (`assets/third_party/icons/`) | Auteur | Fichier d'origine (dépôt game-icons/icons) |
|---|---|---|
| `weapon_revolver.svg` | delapouite | `delapouite/revolver.svg` |
| `weapon_pistol.svg` | john-colburn | `john-colburn/pistol-gun.svg` |
| `weapon_shotgun.svg` | sbed | `sbed/shotgun.svg` |
| `weapon_rifle.svg` | sbed | `sbed/rifle.svg` |
| `weapon_winchester.svg` | skoll | `skoll/winchester-rifle.svg` |
| `weapon_musket.svg` | skoll | `skoll/musket.svg` |
| `weapon_bow.svg` | delapouite | `delapouite/bow-arrow.svg` |
| `weapon_crossbow.svg` | carl-olsen | `carl-olsen/crossbow.svg` |
| `weapon_bowie_knife.svg` | lorc | `lorc/bowie-knife.svg` |
| `weapon_dagger.svg` | lorc | `lorc/plain-dagger.svg` |
| `weapon_curved_knife.svg` | lorc | `lorc/curvy-knife.svg` |
| `weapon_katana.svg` | delapouite | `delapouite/katana.svg` |
| `weapon_sword.svg` | lorc | `lorc/broadsword.svg` |
| `weapon_axe.svg` | lorc | `lorc/battle-axe.svg` |
| `weapon_tomahawk.svg` | delapouite | `delapouite/tomahawk.svg` |
| `weapon_hammer.svg` | delapouite | `delapouite/warhammer.svg` |
| `weapon_spear.svg` | lorc | `lorc/spear-hook.svg` |
| `weapon_whip.svg` | lorc | `lorc/whip.svg` |
| `weapon_lasso.svg` | delapouite | `delapouite/lasso.svg` |
| `weapon_dynamite.svg` | delapouite | `delapouite/dynamite.svg` |
| `weapon_fire_bomb.svg` | lorc | `lorc/fire-bomb.svg` |
| `ammo_bullets.svg` | lorc | `lorc/bullets.svg` |
| `ammo_box.svg` | sbed | `sbed/ammo-box.svg` |
| `ammo_powder.svg` | lorc | `lorc/powder.svg` |
| `key_basic.svg` | lorc | `lorc/key.svg` |
| `key_skeleton.svg` | lorc | `lorc/skeleton-key.svg` |
| `lock_padlock.svg` | lorc | `lorc/padlock.svg` |
| `lock_lockpicks.svg` | delapouite | `delapouite/lockpicks.svg` |
| `container_chest.svg` | delapouite | `delapouite/chest.svg` |
| `container_chest_locked.svg` | lorc | `lorc/locked-chest.svg` |
| `container_chest_open.svg` | skoll | `skoll/open-treasure-chest.svg` |
| `container_chest_mimic.svg` | delapouite | `delapouite/mimic-chest.svg` |
| `container_crate.svg` | delapouite | `delapouite/wooden-crate.svg` |
| `container_barrel.svg` | delapouite | `delapouite/barrel.svg` |
| `container_coffin.svg` | lorc | `lorc/coffin.svg` |
| `container_wagon.svg` | delapouite | `delapouite/old-wagon.svg` |
| `rarity_gem.svg` | lorc | `lorc/cut-diamond.svg` |
| `rarity_star.svg` | delapouite | `delapouite/star-medal.svg` |
| `loot_coins.svg` | delapouite | `delapouite/two-coins.svg` |
| `loot_gold_bar.svg` | willdabeast | `willdabeast/gold-bar.svg` |
| `loot_bag.svg` | lorc | `lorc/swap-bag.svg` |
| `stat_heart.svg` | skoll | `skoll/hearts.svg` |
| `stat_heart_plus.svg` | zeromancer | `zeromancer/heart-plus.svg` |
| `stat_shield.svg` | sbed | `sbed/shield.svg` |
| `stat_armor.svg` | lorc | `lorc/leather-vest.svg` |
| `stat_speed.svg` | lorc | `lorc/sprint.svg` |
| `stat_power.svg` | delapouite | `delapouite/mighty-force.svg` |
| `stat_stopwatch.svg` | lorc | `lorc/stopwatch.svg` |
| `item_health_potion.svg` | delapouite | `delapouite/health-potion.svg` |
| `item_backpack.svg` | lorc | `lorc/knapsack.svg` |
| `item_map.svg` | lorc | `lorc/treasure-map.svg` |
| `item_magnifier.svg` | lorc | `lorc/magnifying-glass.svg` |
| `item_holster.svg` | delapouite | `delapouite/cowboy-holster.svg` |
| `world_door.svg` | lorc | `lorc/wooden-door.svg` |
| `world_exit_door.svg` | delapouite | `delapouite/exit-door.svg` |
| `world_saloon_doors.svg` | delapouite | `delapouite/saloon-doors.svg` |
| `world_stairs.svg` | delapouite | `delapouite/stairs.svg` |
| `world_bank.svg` | delapouite | `delapouite/bank.svg` |
| `world_gold_mine.svg` | delapouite | `delapouite/gold-mine.svg` |
| `world_cactus.svg` | delapouite | `delapouite/cactus.svg` |
| `world_campfire.svg` | lorc | `lorc/campfire.svg` |
| `world_tombstone.svg` | lorc | `lorc/tombstone.svg` |
| `world_wanted.svg` | delapouite | `delapouite/wanted-reward.svg` |
| `skull_crossbones.svg` | lorc | `lorc/skull-crossed-bones.svg` |
| `skull_death.svg` | sbed | `sbed/death-skull.svg` |
| `enemy_bandit.svg` | delapouite | `delapouite/bandit.svg` |
| `enemy_golem.svg` | delapouite | `delapouite/rock-golem.svg` |
| `enemy_golem_head.svg` | delapouite | `delapouite/golem-head.svg` |
| `mask_fox.svg` | lorc | `lorc/fox-head.svg` |
| `mask_robber.svg` | delapouite | `delapouite/robber-mask.svg` |
| `mask_skull.svg` | lorc | `lorc/skull-mask.svg` |
| `mask_iron.svg` | lorc | `lorc/iron-mask.svg` |
| `mask_puppet.svg` | lorc | `lorc/puppet.svg` |
| `mask_spectre.svg` | lorc | `lorc/spectre.svg` |
| `power_lightning.svg` | delapouite | `delapouite/bolt-spell-cast.svg` |
| `power_fire_ring.svg` | lorc | `lorc/fire-ring.svg` |
| `alert_hazard.svg` | lorc | `lorc/hazard-sign.svg` |
| `ui_settings.svg` | lorc | `lorc/cog.svg` |
| `ui_pause.svg` | guard13007 | `guard13007/pause-button.svg` |
| `ui_upgrade.svg` | delapouite | `delapouite/upgrade.svg` |

---

## Sources examinées mais non intégrées

| Source | Raison |
|---|---|
| Kenney Impact Sounds / RPG Audio / Sci-fi Sounds (versions Godot de Loppansson et Calinou sur GitHub) | Licence OK (CC0), mais dépôts inaccessibles via le proxy de la session (403). kenney.nl est aussi bloqué. Pas de contournement par miroir. |
| Paquet npm `@netforge/asset-library-files` | Contient des sons Kenney CC0 ré-encodés, mais c'est un miroir tiers : écarté (consigne : sources officielles seulement). |
| Paquet npm `@wubbleai/community-sfx` / `uisfx` | CC0, mais sons d'interface synthétiques, peu adaptés au western ; doublon des sons UI de Kenney. |
| Musique « Battle Theme A » (cynicmusic, OpenGameArt, CC0) | opengameart.org bloqué par le proxy. |
| Polices Sancreek (OFL) | Licence OK. Rye a été préférée, plus lisible en petit. Disponible dans google/fonts si besoin. |
| Police Smokum | Absente du dépôt google/fonts (404). |
| Fredoka (OFL) | Licence OK, mais Nunito est plus sobre et plus lisible pour le texte courant. |
| Tilesets/props Superpowers `western-fps-2d` | CC0, mais en **pixel-art** 32×32 et vue FPS de face : incompatible avec la direction artistique (rendu peint, vue de dessus 3/4). Non intégré. |
| Tilesets Kenney (Tiny Town, etc.) | Pixel-art ou style trop différent ; de plus kenney.nl est inaccessible. |
