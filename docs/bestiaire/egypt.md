# Bestiaire — Les Pyramides d'Égypte (« Le royaume des morts »)

D'après la colonne de droite de `docs/reference/bestiaire_mondes_4_6.png`. Agent Égypte, branche
`feature/bestiaire-mondes-4-6`, contrat `docs/bestiaire/CONTRAT_MONDES_4_6.md`. Le monde n'a pas encore
de carte : le bestiaire est décrit dans `data/bestiary/egypt.tres` (BestiaryData), prêt à être recopié
dans le futur WorldData. Aucune carte, aucun WorldData, aucun BiomeRegistry touchés.

## Pipeline Blender
`art/blender/bestiary/egypt/build_eg_bestiary.py` (autonome ; même caméra orthographique 3/4 à 48°,
même échelle monde 0,577 unité/px, même contour Freestyle et matériaux toon peints que le héros, via
`art/blender/rdm_common.py` ; lumière chaude du projet). Palette de la planche : os, bandelettes de lin,
or et lapis-lazuli, bronze, sable ocre ; accents émissifs (yeux ambrés, disques solaires).

| Rig | Kinds |
|---|---|
| `EgHuman` (humanoïde + armes tenues : joint d'arme placé à la main issue de l'IK, rotation dans le repère de la colonne) → `Skeleton`, `Archer`, `Mummy`, `Jackal`, `Priest`, `Pharaoh` | squelettes, momie, élites, boss |
| `Scarab` (élytres, pronotum, tête cornue, mandibles, 6 pattes en IK, mort sur le dos) | Scarabée géant |
| `Lizard` (corps + queue = un tube refait à chaque pose le long d'une colonne souple, tête à mâchoire, collerette, épines, 4 pattes écartées en IK) | Lézard des sables |
| `Viper` (anneaux enroulés + cou dressé = un tube refait à chaque pose, capuchon ocellé ; rampe allongée en course) | Vipère des sables |

```
flock /home/claude/.blender_render.lock python3 art/blender/bestiary/egypt/build_eg_bestiary.py [--kinds eg_skeleton,...]
... --preview se,n --anim idle:0,attack:3 --kinds eg_mummy     # aperçu rapide (RDM_TMP)
... --repack --kinds eg_skeleton                               # atlas + méta depuis les images rendues
... --sheet                                                    # planche de présentation (captures)
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup / tir, 4-5 retour),
hit (3), death (8, dernière image = cadavre) × 8 directions. Cadre 192 px ; momie et élites 224 px ;
boss rendu 448 px (échelle ×2,5 : ≈ 2,5 fois un squelette en jeu) stocké à 62 % (`world_per_px` 0,94
compensé, atlas 2048 × 3268 < 8192) avec idle 4 / run 6 / death 6 images. Silhouette du boss : grand
némès rayé or / lapis, masque d'or, large collier ousekh, cape sombre, sceptre au disque solaire, halo
doré émissif. La planche de présentation le montre à l'échelle du jeu à côté d'un squelette.
Sorties : `assets/sprites/enemies/<kind>/` (`_atlas.png` compression VRAM, `_frames.tres`, `_meta.json`).

## Monstres communs (rangée 1 = plus simples, rangée 2 = plus durs)

| Kind | Nom | PV | Vitesse | Attaque | Compétences |
|---|---|---|---|---|---|
| `eg_skeleton` | Squelette rôdeur | 55 | 128 (moyenne) | khopesh, mêlée 9 ; rôde loin (patrouille 170 px), cherche longtemps (5,5 s) | `eg_spike_trap` (actionne un piège ancien : pointes sous le joueur, 10 + entrave 0,7 s) |
| `eg_scarab` | Scarabée géant | 95 | 118 | morsure 11 | `charge` (couloir, 560 px/s, 18 + renversement), `hard_skin` (carapace −30 % de face) |
| `eg_lizard` | Lézard des sables | 70 | 205 (rapide, zigzag) | ruée + 2 morsures (7) | `eg_burrow` (s'enfouit, file sous le sable, intouchable, jaillit sous le joueur : 13) |
| `eg_archer` | Archer sable | 75 | 105 | tir précis 14 (ligne de visée, 760 px/s, portée 540), garde ses distances, couverts | `eg_arrow_rain` (3 zones de flèches, 11), `eg_temple_call` (corne : 2 renforts squelette / scarabée) |
| `eg_mummy` | Momie étouffée | 230 | 78 (lente) | frappe à deux poings 18 | `eg_undying` (se relève une fois à 50 % PV, plus rapide), `eg_bandage_lash` (bandelette : happe, tire vers elle, entrave) |
| `eg_viper` | Vipère des sables | 120 | 195 (rapide) | morsure en ruée 12 ; ouïe 540 px (embuscade) | `eg_venom` (passif : venin cumulable), `eg_burrow` (embuscade + venin), `eg_venom_spit` (flaque de venin) |

Comportements communs de la planche :
- **se déplacent en groupes** : rayons d'alerte des voisins élevés (320 à 520 px) ; la section
  `[bestiary_egypt]` porte `group_chance` / `group_size` pour le générateur de la future carte (même
  principe que `mall_populator.gd::_group_cells`) ;
- **utilisent les pièges et les mécanismes anciens** : `eg_spike_trap`, `eg_arrow_rain`, `eg_venom_spit`
  (frappes au sol différées, `eg_glyph.gd`) ;
- **appellent des renforts des temples** : `eg_temple_call` (Archer, Prêtre), `eg_raise_dead` (Pharaon).

## Élites (`elite = true`, `BestiaryData.elite_kinds`)
| Kind | Nom | PV | Attaque | Compétences |
|---|---|---|---|---|
| `eg_shadow_warrior` | Guerrier de l'ombre (tête de chacal) | 560 | khopesh : ruée + 3 coups (13) ; phase 2 sous 50 % | `eg_shadow_veil` (camouflage 4 s : quasi invisible, +40 % vitesse, connaît la position du joueur, 1er coup ×1,6), `rush`, `dodge_roll` |
| `eg_sun_priest` | Prêtre du soleil | 460 | éventail de 3 orbes solaires (12), garde ses distances ; phase 2 sous 50 % | `eg_solar_blessing` (soigne 20 % et galvanise les alliés à 300 px), `eg_sun_flare` (éruption solaire : 16 + aveuglement), `eg_temple_call` (squelette / archer) |

## Boss : `eg_pharaoh` — Le Pharaon éternel, « Souverain éveillé du royaume des morts »
4200 PV (7,5 × le Guerrier de l'ombre), frappe de zone au sceptre (150 px, 28), jamais étourdi,
invulnérable 1,5 / 2 s aux transitions.

| Phase | PV | Compétences | Entrée | Multiplicateurs |
|---|---|---|---|---|
| 1 — Le jugement | 100 → 70 % | `eg_curse` (3 malédictions de zone : 16 + ralentissement), `eg_sun_flare` (140 px, aveugle), `shockwave` | — | — |
| 2 — Le réveil des morts | 70 → 30 % | `eg_raise_dead` (3 momies / squelettes / archers, max 6), `eg_sandstorm` (2 tourbillons qui dérivent : ralentit, aveugle, masque), `eg_curse`, `teleport`, `shockwave` | réveil des morts | vitesse ×1,1, recharge ×0,85, dégâts ×1,15 |
| 3 — La colère éternelle | 30 → 0 % | `eg_sun_rays` (8 rayons × 2 salves décalées : 22 + brûlure), `eg_raise_dead` (dont vipère et Guerrier de l'ombre, max 7), `eg_sandstorm`, `eg_curse` ×5, `teleport`, `shockwave` | rayons du soleil | vitesse ×1,3, recharge ×0,6, dégâts ×1,45 |

## Compétences propres (`scripts/enemies/skills/egypt/`, déclarées dans `registry.gd`)
- `eg_glyph_strike_skill.gd` — frappes au sol différées (`eg_glyph.gd` : cercle à motif, frappe, flaque
  facultative) ; ids `eg_spike_trap`, `eg_arrow_rain`, `eg_sun_flare`, `eg_curse`, `eg_venom_spit`.
- `eg_burrow` — embuscade sous le sable (intouchable, quasi invisible, cercle de sortie, éruption ; venin en option).
- `eg_temple_call` — hérite du sifflet commun : cri, cercles sonores, alerte, renforts `kinds` par la porte la plus proche.
- `eg_raise_dead` — invocation de morts-vivants autour du lanceur (colonnes de sable).
- `eg_undying` — résurrection unique (coup mortel absorbé, animation de mort tenue, relevée à 50 %).
- `eg_bandage_lash` — couloir, happe le premier joueur : dégâts, renversement dirigé vers la momie, entrave.
- `eg_venom` (passif) + `eg_venom_dot.gd` (`EgVenomDot`) — poison attaché au joueur (doses cumulables, ralentit).
- `eg_sandstorm` + `eg_sandstorm.gd` — tourbillons de sable dérivants.
- `eg_shadow_veil` — camouflage et frappe d'embuscade.
- `eg_solar_blessing` — soin + galvanisation des alliés (vitesse, cadence) pour `duration` s.
- `eg_sun_rays` — rayons solaires en étoile, salves décalées.
- `eg_fx.gd` — effets visuels brefs (halo solaire, sable, malédiction, rayon, résurrection).
Compétences communes réutilisées : `charge`, `hard_skin`, `rush`, `dodge_roll`, `shockwave`, `teleport`.
Valeurs par défaut : `[bestiary_egypt]` de `data/balance.cfg` (clé `<id>_<paramètre>`, lues par
`eg_bal.gd`) ; les `.tres` les remplacent. Effets visuels : placeholders dessinés en code.

## Roster (`data/bestiary/egypt.tres`)
- Rangée 1 (squelette, scarabée, lézard) : combat, couloirs, fouille, extraction (squelette partout, seul
  à l'entrée ; squelette / scarabée en salle de repos).
- Rangée 2 (archer, momie, vipère) : combat, extraction, trésor (momies et archers gardes), pièges (vipères
  en embuscade) ; peu ou pas en fouille et en repos. `[bestiary_egypt] row2_kinds` pour un éventuel
  multiplicateur par étage.
- Élites / boss : `elite_kinds = [eg_shadow_warrior, eg_sun_priest]`, `boss_kind = eg_pharaoh`.
- Butin : `data/loot_tables/enemy_eg_pharaoh.tres` (table propre du boss, exigée par
  `tests/test_boss_loot.gd` : 4 à 6 objets, jamais vide, Épiques et Légendaires possibles ; objets
  génériques — or, diamant, bandages, carte au trésor, armes — faute d'objets propres au monde). Les
  autres ennemis retombent sur la table du biome / la table générique (tables à créer avec la carte et
  ses objets).

## Changements partagés
- `data/balance.cfg` : ajout de la section `[bestiary_egypt]` en fin de fichier (additif).
- Aucun autre fichier partagé modifié. Points d'attention pour le chef de projet :
  - `EgVenomDot` (`class_name`) s'attache comme enfant du joueur ; en coop seul l'hôte l'applique (les
    dégâts passent par `EnemySkills.hit_player`), l'invité ne voit pas les bulles.
  - `eg_undying` et `eg_burrow` appellent `_play_once` / `set_modulate` sur le visuel via `_visual_call` :
    relayés à l'invité par `NetHooks.on_enemy_visual` seulement si la coop sait les rejouer (comme les
    opacités du centre commercial).
  - Les nœuds `eg_glyph`, `eg_fx`, `eg_sandstorm` ne sont pas relayés en coop (visuels côté hôte).

## Tests
`tests/test_bestiary_egypt.gd` : données, planches 8 directions, noms et traits de la planche, rangée 2
plus dure, compétences connues et préfixées, renforts existants, BestiaryData (roster, 2 élites, boss),
boss en 3 phases (1,0 / 0,7 / 0,3, phase 3 enragée, PV), et comportements : piège, charge, embuscade
sous le sable, pluie de flèches + renforts, résurrection unique de la momie, bandelette, venin, flaque,
voile d'ombre, bénédiction, éruption solaire, phases du boss (réveil des morts, rayons), tempête.

## Captures (`docs/bestiaire/captures/egypt/`)
- `planche_modeles_egypt.png` — les 9 modèles (idle, attaque, cadavre).
- `en_jeu_classiques_repos.png`, `en_jeu_classiques_combat_0..3.png` — les 6 communs ;
  `competences_telegraphes.png`, `competences_effets.png` — piège, pluie de flèches, bandelette,
  crachat de venin, embuscade sous le sable ; `momie_effondree.png`, `momie_relevee.png` — résurrection ;
  `en_jeu_elites_repos.png`, `en_jeu_elites_benediction_voile.png`, `en_jeu_elites_eruption_solaire.png` ;
  `boss_repos.png`, `boss_phase1_malediction.png`, `boss_phase2_reveil_des_morts.png`,
  `boss_phase2_tempete.png`, `boss_phase3_rayons_telegraphe.png`, `boss_phase3_rayons.png`.
  Arène de test dans un raid de Dust Creek (le monde n'a pas de carte) : brouillard levé, interface
  masquée, joueur invulnérable. Script de capture (hors dépôt) : scène lancée par `--script` sous xvfb.
