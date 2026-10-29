# Bestiaire — Centre commercial abandonné (« Les égarés de la nuit »)

Refonte d'après `docs/reference/bestiaire_classique.png` et `docs/reference/bestiaire_elites_boss.png`
(colonne CENTRE COMMERCIAL ABANDONNÉ). Agent Centre commercial, branche `feature/bestiaire`.
La carte du centre commercial reste masquée du choix des cartes (`[maps] only_ids`, inchangé).

## Pipeline Blender
`art/blender/bestiary/mall/build_mall_bestiary.py` (autonome ; même caméra orthographique 3/4 à 48°,
même échelle monde 0,577 unité/px, même contour Freestyle et matériaux toon peints que le héros,
via `art/blender/rdm_common.py`). Lumière de nuit légèrement rosée, accents émissifs violets / rouges.

| Rig | Kinds |
|---|---|
| `Human` (joints + IK 2 os des bras), variantes `Zombie`, `Flayer`, `SecBot`, `Clone`, `Brute`, `Violent`, `Warden` | humanoïdes |
| `Spider` (céphalothorax, abdomen, chélicères, 8 pattes en IK 2 os, marche en tétrapode) | Nuit blanche |
| `Omnistore` (masse de chair, tête + mâchoire, 3 écrans, 2 faux, 6 pattes en IK) | boss |

```
flock /home/claude/.blender_render.lock python3 art/blender/bestiary/mall/build_mall_bestiary.py [--kinds mall_zombie,...]
... --preview s,se --anim idle:0,attack:3 --kinds mall_brute     # aperçu rapide (RDM_TMP)
... --repack --kinds mall_zombie                                 # atlas + méta depuis les images rendues
... --sheet                                                      # planche de présentation (captures)
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup/tir, 4-5 retour),
hit (3), death (8, dernière image = cadavre) × 8 directions. Cadre 192 px ; Gros brute 256 px ;
élites 224 px. Boss : rendu 384 px, stocké à 72 % (276 px, `world_per_px` compensé dans la méta)
avec idle 4 / run 6 / death 6 images, pour garder l'atlas à 2048 × 5152 (< 8192, mobile).
Sorties : `assets/sprites/enemies/<kind>/` (`_atlas.png` compression VRAM, `_frames.tres`, `_meta.json`).

## Monstres classiques (rangée 1 = plus simples, rangée 2 = plus durs)

| Kind | Nom | PV | Vitesse | Détection (vue / ouïe) | Attaque | Compétences |
|---|---|---|---|---|---|---|
| `mall_zombie` | Zombie | 60 | 82 (lent) | 300 px, 150° / 460 px | mêlée 10, prévient les voisins à 420 px | `rush` (titube vers la cible) |
| `mall_flayer` | Écorcheur | 70 | 182 | 400 px / 420 px | ruée + 2 entailles (9) | `mall_pounce` (bond, 15 dans 62 px) |
| `mall_security_bot` | Sécurité robot | 150 | 112 | 470 px, 120° / 340 px | rafale de 3 (7), ligne de visée, garde ses distances | `mall_alarm` (2 renforts zombie / écorcheur, alerte les voisins), `hard_skin` (blindage −20 % de face) |
| `mall_clone` | Clone | 75 | 190 | 420 px / 380 px | estoc au couteau (14, télégraphe 0,3 s) | `mall_illusion` (2 doubles + quasi-invisible 1,8 s), `mall_shadow_step` (réapparaît dans le dos du joueur) |
| `mall_brute` | Gros brute | 300 | 78 (lent) | 360 px / 380 px | frappe au sol, zone 115 px (22) | `shockwave` (240 px, renverse), `hard_skin` (−35 % de face au contact), `charge` |
| `mall_night_spider` | Nuit blanche | 80 | 205 | 230 px, 120° / **700 px** (ouïe ×3,6) | morsure en ruée (12) | `mall_shadow_skin` (translucide hors attaque), `mall_pounce` (bond, immobilise 0,6 s) |

Comportements communs de la planche :
- **se regroupent par zones** : `mall_populator.gd::_group_cells` place les ennemis d'une salle en
  groupes de `group_size` cases voisines (`[bestiary_mall] group_chance`, `group_size`) ;
- **lumière et obscurité** : Nuit blanche translucide dans l'ombre, illusions et pas de l'ombre du
  Clone, invisibilité du Violent ; ambiance de nuit du biome ;
- **renforts (alarme)** : `mall_alarm` (gyrophare « beep », message, alerte des voisins, renforts par
  la porte la plus proche).

Données internes (pas des monstres du roster) : `mall_clone_illusion` (double du Clone, kind visuel
`mall_clone`, 1 PV) et `mall_omnistore_illusion` (mirage du boss, kind visuel `mall_omnistore`,
`boss = false`). Passif `mall_illusion_body` : se dissipent au premier coup, après 2 attaques ou
10 s — sans cadavre, sans butin, sans `enemy_died`.

## Élites (`elite = true`, `WorldData.elite_kinds`)
| Kind | Nom | PV | Attaque | Compétences |
|---|---|---|---|---|
| `mall_violent` | Le Violent (éclaireur corrompu) | 460 | griffes acérées : ruée + 3 coups (13), phase 2 sous 50 % | `charge` (charge rapide, renverse), `mall_cloak` (invisibilité temporaire 3,5 s, +35 % vitesse, cesse au coup donné ou reçu), `mall_pounce` |
| `mall_store_warden` | Le Gardien de magasin (robot de sécurité) | 520 | tir de précision (20, ligne de visée, 900 px/s), phase 2 : rafales | `energy_shield` (bouclier −85 % de face, 3,5 s), `mall_alarm` (2 renforts robot / écorcheur) |

## Boss : `mall_omnistore` — L'Omnistore, « Entité de consommation corrompue »
3200 PV, frappe de zone (150 px, 26), invulnérable 1,2-1,5 s aux transitions, pas d'étourdissement.

| Phase | PV | Compétences | Entrée | Multiplicateurs |
|---|---|---|---|---|
| 1 — Panique | 100 → 70 % | `mall_panic_wave` (2 ondes 440 px : blind + slow), `mall_illusion` (2 mirages), `shockwave` | — | — |
| 2 — Appel des consommables | 70 → 30 % | `mall_alarm` (3 créatures du magasin, max 7), `teleport` (entre les zones), ondes, `shockwave` | appel | vitesse ×1,15, recharge ×0,85, dégâts ×1,1 |
| 3 — Surcharge | 30 → 0 % | `mall_overload` (3 ondes 220/350/480 px, 22, renverse), appel, téléportation, ondes, `shockwave` | surcharge | vitesse ×1,3, recharge ×0,65, dégâts ×1,4 |

Arène de la planche : « Galeries marchandes — Niveau central ». La salle boss du générateur reste
le bloc de la direction (étage 2, `mall_layout.gd`), qui est aussi l'étage le plus profond du raid
(`BestiaryRules` garde le boss à cet étage). Proposition au chef de projet si l'on veut coller à la
planche : faire de l'atrium de la galerie haute (étage 1) la salle `boss` — non fait ici, car cela
change le plan pré-rendu du centre commercial (paquet provisoire, tests de correspondance).

## Compétences propres (`scripts/enemies/skills/mall/`, déclarées dans `registry.gd`)
- `mall_pounce` — bond : cercle d'atterrissage (télégraphe), saut, dégâts de zone à l'arrivée (+ statut).
- `mall_alarm` — hérite du sifflet commun : gyrophare, message, alerte des voisins, renforts `kinds`.
- `mall_illusion` — doubles illusoires autour du joueur + quasi-invisibilité, frappe aussitôt.
- `mall_illusion_body` (passif) — corps des illusions (teinte, dissipation).
- `mall_shadow_step` — réapparaît dans le dos du joueur (opposé de sa visée), attaque prête.
- `mall_shadow_skin` (passif) — translucide hors attaque, révélée 1,4 s quand elle est touchée.
- `mall_cloak` — invisibilité temporaire (barre de vie masquée, vitesse ↑).
- `mall_panic_wave` — ondes de panique (danger « shockwave » sans renversement + statuts blind / slow).
- `mall_overload` — surcharge : ondes de choc successives de plus en plus larges.
Compétences communes réutilisées : `rush`, `charge`, `shockwave`, `hard_skin`, `energy_shield`, `teleport`.

## Roster (`data/worlds/world_03_mall.tres`, `mall_populator.gd`)
- Rangée 1 (zombie, écorcheur, robot) : partout (zombie seul au hall d'entrée, robot sauf repos/fouille légère).
- Rangée 2 (clone, gros brute, nuit blanche) : combat, extraction, piège, trésor ; au rez-de-chaussée
  hors combat leurs poids sont ×0,3 (`[bestiary_mall] row2_kinds`, `row2_shallow_mult`).
- Rôles (`ROLE_ROSTER`) : robots aux balcons et au poste de sécurité, clones dans les boutiques de
  vêtements et l'arcade, araignées au cinéma (noir), zombies + brute au parking, robots/brute sur le toit.
- Élites / boss : `elite_kinds = [mall_violent, mall_store_warden]`, `boss_kind = mall_omnistore`.

## Ancien → nouveau (armes `data/weapons/*.tres` non modifiées : `unlock_enemy_kind`)
Aucune arme ne référence d'ancien kind du centre commercial (vérifié). Correspondance si besoin :
`mall_guard` → `mall_security_bot`, `mall_clown` → `mall_zombie`, `mall_mannequin` → `mall_clone`,
`mall_sniper` → `mall_store_warden`, `mall_director` → `mall_omnistore`.

## Supprimé
`data/enemies/mall_{clown,director,guard,mannequin,sniper}.tres`, `assets/sprites/mall/enemies/*.png`,
`art/blender/mall/build_mall_enemies.py` ; `scripts/biomes/mall/enemy_kinds.gd` vidé (`KINDS = {}`,
le bestiaire utilise les planches d'EnemyArt).

## Changements partagés
Aucun fichier partagé modifié. Points d'attention pour le chef de projet :
- Opacité des compétences (`set_modulate` sur le visuel) : non relayée en coop (pas dans
  `NetProtocol.fx_index`) — l'invité voit la Nuit blanche / le Clone / le Violent opaques.
- Les illusions (`*_illusion.tres`) sont libérées sans mourir côté hôte ; en coop, vérifier que la
  marionnette de l'invité disparaît aussi.

## Tests
`tests/test_bestiary_mall.gd` (20 tests : données, planches, roster, regroupement, compétences, élites,
boss, phases) ; `tests/test_mall.gd` adapté (nouveaux kinds, boss générique).

## Captures (`docs/bestiaire/captures/mall/`)
- `planche_modeles_mall.png` — les 9 modèles (idle, attaque, cadavre).
- `en_jeu_classiques_repos.png`, `en_jeu_classiques_combat.png` — les 6 classiques dans un raid du centre commercial.
- `en_jeu_elites_boss_repos.png`, `en_jeu_elites_boss_combat.png` — élites et boss.

## Arène du boss (décision utilisateur, 29/10)
L'Omnistore reste dans le **bureau du directeur** (dernier étage), et non dans l'atrium « Galeries
marchandes — Niveau central » de la planche. Pas de changement du plan du centre commercial.
