# Bestiaire — Station spatiale (« Les machines de l'espace »)

Agent Station, branche `feature/bestiaire`. Références : `docs/reference/bestiaire_classique.png` et
`docs/reference/bestiaire_elites_boss.png` (colonne STATION SPATIALE).

## Étape 1 — bestiaire classique (fait)

| Rangée | Kind | Nom | PV | Vitesse | Attaque de base | Compétences |
|---|---|---|---|---|---|---|
| 1 | `ss_security_droid` | Droïde de sécurité | 50 | 118 | rafale de 3 lasers rouges (5 dmg), garde ses distances à couvert | `deploy_turret` (tourelle), `flash_grenade` |
| 1 | `ss_spectre` | Spectre | 24 | 185 | 2 traits laser cyan en éventail, vol en zigzag | `dodge_roll` (esquive en vol), `kamikaze` sous 40 % PV |
| 1 | `ss_teleporter` | Téléporteur | 55 | 195 | ruée griffue (2 coups) | `ss_blink_strike` (réapparaît dans le dos du joueur et frappe), `teleport` |
| 2 | `ss_detector` | Détecteur | 32 | 140 | petit laser rouge, vision 360° / 580 px, ouïe 560 px | `ss_alarm_scan` (alerte toute la zone à 900 px + appelle 1 droïde) |
| 2 | `ss_station_guardian` | Gardien de station | 200 | 72 | 3 bolts cyan en éventail, avance lentement | `ss_zone_barrage` (4 obus plasma sur cercles télégraphiés), `shockwave`, `ss_drone_launch` (2 spectres) |
| 2 | `ss_alien` | Alien | 180 | 132 | ruée à tentacules (2 coups, 15 dmg) | `ss_frenzy` (furieux de près : vitesse ×1,45, recharges ×0,6), `ss_brood_summon` (2 larves), `rush` |
| — | `ss_alien_brood` | Larve d'alien | 14 | 215 | morsure | `rush` — invoquée uniquement (hors roster) |

Comportements communs de la planche : groupes (rayons d'alerte des voisins 300-620 px), drones (spectres
lancés par le gardien, kamikaze), tourelles (droïde), renforts (détecteur) et téléportation (téléporteur).

### Roster (`data/worlds/world_02_space_station.tres`)
- Rangée 1 (droïde, spectre, téléporteur) dans **tous** les types de salles.
- Rangée 2 (détecteur, gardien, alien) en combat, extraction, super_loot, piège ; peu ou pas ailleurs.
- `[bestiary_space_station]` de `balance.cfg` : `row2_floor_mult` multiplie le poids de la rangée 2 par
  pont (0,6 sur le pont principal, 1,6 au pont des machines −1, 1,3 au pont de commandement +1),
  appliqué par `ss_populator.gd` (`roster_weights`).

### Compétences propres (`scripts/enemies/skills/space_station/`, registre `registry.gd`)
| Id | Script | Effet |
|---|---|---|
| `ss_blink_strike` | `ss_blink_strike_skill.gd` | marqueur bleu + invulnérable pendant le télégraphe, réapparaît derrière le joueur, court élan rouge puis coup |
| `ss_alarm_scan` | `ss_alarm_scan_skill.gd` | balayage + cri, tous les ennemis dans `radius` deviennent alertés sur la position du joueur, débusque un joueur caché, renforts `kinds` |
| `ss_zone_barrage` | `ss_zone_barrage_skill.gd` | `count` cercles de danger autour du joueur puis explosions successives (`blast`) |
| `ss_drone_launch` / `ss_brood_summon` | `ss_summon_skill.gd` | anneaux de pose puis `count` invocations alertées, plafond `max_total` |
| `ss_frenzy` | `ss_frenzy_skill.gd` | passif : frénésie tant que le joueur est à moins de `near` px |

Tous les paramètres sont dans les `.tres` (les valeurs de `defaults()` ne sont que des replis).

### Modèles Blender
`art/blender/bestiary/space_station/build_ss_enemies.py` (pipeline de `art/blender/build_enemies.py` :
caméra 3/4 à 48°, toon peint, contour Freestyle, même densité de pixels que le héros ; pack/SpriteFrames
importés de `build_enemies.py`). Rigs : `Mech` (humanoïdes en IK : droïde, téléporteur, gardien, Atlas ;
variante `gaunt` pour le téléporteur : créature décharnée gris-bleu aux membres galbés, cœur bleu et éclairs ;
variante `orb` pour L'Architecte : torse-sphère à énorme œil rouge central, antennes, ailerons, bras-canons
doubles écartés), `Spectre` (sphère volante, œil bleu relevé vers la caméra, boulons de coque, 7 tentacules
mécaniques segmentées à griffes), `Spider` (variante `orb_body` : corps-sphère porté haut, gros œil rouge,
6 pattes blindées à lames — Détecteur anthracite, Drone Tieur plus massif aux lames ivoire et canons
latéraux), `Alien` (créature à crâne haut bosselé, yeux magenta, arcades froncées, 8 pattes-tentacules et
2 bras griffus : adulte ; la larve est le même rig en petit). Les lueurs (yeux, cœurs, canons) sont émissives
avec un point chaud quasi blanc au centre (lisible sur mobile) et s'éteignent sur les dernières images de la mort.

Palette (refonte de fidélité aux planches) : métal « gunmetal » anthracite (`SS_MATS`), seuil toon relevé
(`BAND` 0,62 : vues de dessus, les faces supérieures gardent le ton de base au lieu du reflet clair) et
liseré de contre-jour bleu froid (`RIM_COLOR`, éclairage de la station) au lieu du liseré chaud commun.

```
source tools/prerender/mac_env.sh
flock "$BLENDER_LOCK" python3 art/blender/bestiary/space_station/build_ss_enemies.py [--kinds ...]
RDM_TMP=<dossier> flock "$BLENDER_LOCK" python3 art/blender/bestiary/space_station/build_ss_enemies.py \
    --preview s,se --anim idle:0,attack:3 --kinds ss_alien     # aperçu rapide
python3 art/blender/bestiary/space_station/build_ss_enemies.py --sheet   # planche de présentation
```
Cadres : 192 px (droïde, spectre, téléporteur, détecteur), 224-256 px (gardien, alien, élites), 160 px (larve).
L'Architecte est rendu à densité réduite (`px_scale` 0,4375, cadre 280 px, même `display_height` qu'avant : 369 unités) : environ 2,5×
la taille d'un droïde en jeu tout en gardant un atlas sous 4096 px (limite GPU mobile).

### Fidélité aux planches (revue du 31/10/2026)
Chaque modèle comparé à son illustration (planche à gauche, rendu jeu s / se, idle et attaque à droite),
noté sur 6 critères (silhouette, couleurs, matières, accessoires, posture, lisibilité) ; seuil 7,5/10.
Comparaisons finales : `captures/space_station/comparaison_planches.png`.

| Kind | Note de départ | Note finale | Décision | Changements principaux |
|---|---|---|---|---|
| `ss_security_droid` | 5,0 | 7,6 | refait (4 essais) | métal sombre, casque/épaulières argent, torse élargi, fusil ×1,4 tenu en travers |
| `ss_spectre` | 5,0 | 7,5 | refait (3 essais) | œil bleu relevé vers la caméra, boulons, 7 tentacules segmentées à griffes |
| `ss_teleporter` | 3,5 | 7,5 | refait (6 essais) | créature décharnée (membres galbés), voûtée, bras écartés, griffes longues, éclairs du cœur |
| `ss_detector` | 4,5 | 7,6 | refait (4 essais) | corps-sphère à gros œil rouge, 6 pattes blindées à lames, genoux hauts |
| `ss_station_guardian` | 5,0 | 7,5 | refait (6 essais) | gorille mécanique voûté, œil bleu unique, épaulières caisson, canons d'avant-bras nervurés |
| `ss_alien` | 3,5 | 7,5 | refait (7 essais) | rig `Alien` (8 pattes-tentacules) au lieu du bipède, crâne haut bosselé, yeux magenta, griffes |
| `ss_drone_tieur` | 4,0 | 7,5 | refait (5 essais) | araignée à corps-sphère au sol (plus d'hélices), pattes-faux ivoire, canons latéraux |
| `ss_atlas` | 5,0 | 7,5 | refait (5 essais) | gabarit ×1,10, épaulières caisson à projecteurs, visière en V et cœur bleus, bouclier physique retiré (l'`energy_shield` reste) |
| `ss_architect` | 5,5 | 7,5 | refait (4 essais) | métal sombre, canons doubles longs et écartés tenus à l'horizontale |

`ss_alien_brood` (hors planche) re-rendu avec la nouvelle palette. Aucune donnée de jeu modifiée
(stats, `body_radius`, cadres inchangés).

## Anciens monstres supprimés
`space_android`, `space_brute`, `space_drone`, `space_soldier` : `.tres`, PNG + `.import` de
`assets/sprites/space_station/enemies/`, entrées de `enemy_kinds.gd`, références de `test_space_station.gd`.
Étape 2 : `space_reactor_colossus` (`.tres`, PNG) et l'ancien script `art/blender/space_station/build_enemies.py`
supprimés ; `enemy_kinds.gd` ne déclare plus aucun sprite (tout le bestiaire est en planches) ;
docstring de `art/blender/space_station/build_tiles.py` mise à jour.

Correspondance ancien → nouveau kind (aucune arme n'avait d'`unlock_enemy_kind` station) :
`space_soldier` → `ss_security_droid`, `space_drone` → `ss_spectre`, `space_android` → `ss_teleporter`,
`space_brute` → `ss_station_guardian`, `space_reactor_colossus` → `ss_architect` (boss).

## Changements partagés
- `scripts/combat/enemy_projectile.gd` : `STYLE_COLORS` += `laser_red` (rouge) et `plasma` (violet) — additif.
- `tests/test_enemy_skills.gd` : les tests génériques utilisaient les anciens kinds de la station ;
  remplacés par les nouveaux qui portent la même compétence (`flash_grenade`/`deploy_turret` →
  `ss_security_droid`, `kamikaze` → `ss_spectre`, `teleport` → `ss_teleporter`, `shockwave` →
  `ss_station_guardian`). Aucun autre changement.

## Étape 2 — élites et boss (fait)

`elite_kinds = [ss_drone_tieur, ss_atlas]`, `boss_kind = ss_architect` dans le WorldData (placement,
barre de boss, règle « un seul boss » : chef de projet).

| Kind | Rôle | PV | Vitesse | Base | Compétences |
|---|---|---|---|---|---|
| `ss_drone_tieur` | Le Drone Tieur — drone d'élite | 150 | 150 | tir ciblé (`aimed`, ligne de visée, 14 dmg, 800 px/s), phase 2 en rafales | `fan_volley` (mise à feu rapide : 8 lasers en 0,4 s), `dodge_roll` ; vol stationnaire (strafe 0,15, sniper) |
| `ss_atlas` | Le Sécurité Atlas — robot lourd | 400 | 95 | rafales de 4 (fusil lourd) | `energy_shield` frontal (90 %), `fan_volley` (tir de suppression : 12 balles sur 60°), `rush` de proximité (renverse) |
| `ss_architect` | L'Architecte — « IA de défense de la station » (boss) | 3000 | 70 | éventail de 5 lasers rouges (phase 3 : rafales) | voir phases |

Phases de L'Architecte (`phases`, format de `enemy_data.gd`) :
1. **100 → 70 % — Apparition + lasers** : `ss_orbital_laser` (couloir de visée puis rayon 1100 px qui
   s'arrête aux murs), `shockwave` au contact.
2. **70 → 30 % — Drones + bouclier** (entrée : `ss_drone_launch` + `energy_shield`) : 3 drones
   (2 spectres + 1 droïde, 4 vivants max), bouclier omnidirectionnel (−75 % de dégâts 5 s), laser,
   `ss_zone_barrage` (5 obus). Vitesse ×1,1, recharges ×0,85.
3. **30 → 0 % — Overload + pattern d'attaques** (entrée : `ss_overload`) : surcharge (1,8 s d'anneau puis
   explosion 240 px / 40 dmg + onde qui renverse jusqu'à 460 px, toutes les 14 s), laser qui balaie 70°,
   barrage de 6 obus, renforts spectre + Drone Tieur, bouclier, onde de choc. Vitesse ×1,25,
   recharges ×0,7, dégâts ×1,3. Invulnérabilité 1,5 s à chaque transition.

Nouvelles compétences : `ss_orbital_laser` (`ss_orbital_laser_skill.gd`), `ss_overload`
(`ss_overload_skill.gd`).
Arène : « Centre de contrôle — Station orbitale » (salle du réacteur actuelle, gérée par le chef de projet).

## Captures
`docs/bestiaire/captures/space_station/` :
- `planche_classiques.png`, `planche_elites_boss.png`, `planche_modeles.png` (les 9 modèles + la larve) ;
- `en_jeu_classiques_repos.png`, `en_jeu_classiques_combat.png`, `en_jeu_elites_boss_repos.png`,
  `en_jeu_elites_boss_combat.png` (raid de la station, brouillard levé, HUD caché).
