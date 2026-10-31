# Bestiaire — Carnaval hanté (« Le parc maudit »)

D'après la colonne de gauche de `docs/reference/bestiaire_mondes_4_6.png` (CANARVAL HANTÉ). Agent
Carnaval, branches `feature/bestiaire-mondes-4-6` puis `feature/refonte-bestiaires`. Le monde n'a pas encore de carte : le bestiaire est
décrit dans `data/bestiary/carnival.tres` (`BestiaryData`), prêt à être recopié dans le WorldData.

## Pipeline Blender
`art/blender/bestiary/carnival/build_cv_bestiary.py`. Il **importe** le pipeline générique du centre
commercial (`art/blender/bestiary/mall/build_mall_bestiary.py` : rig humanoïde à IK 2 os, rendu,
empaquetage de l'atlas, méta, SpriteFrames) et y ajoute ses propres classes ; donc même caméra
orthographique 3/4 à 48°, même échelle monde 0,577 unité/px, même contour Freestyle et matériaux
toon peints que le héros (`art/blender/rdm_common.py`). Lumière de nuit légèrement rosée, accents
émissifs violets / rouges (néons, yeux, flammes, grande roue).

| Rig | Kinds |
|---|---|
| `CvHuman` (humanoïde mall + collerettes, ballons qui suivent la main, flammes vacillantes) : `LostClown`, `Acrobat`, `Penumbra`, `BigPlush`, `FairgroundBeing`, `FireClown`, `CircusKing` | humanoïdes |
| `Quad` (torse horizontal en loft, cou / tête / mâchoire, 4 pattes en IK 2 os, queue) : `CircusDog` | Chien de cirque |
| `GhostCarousel(Quad)` : cheval de bois sur sa barre dorée torsadée, pied lumineux, pattes figées en galop de manège | Manège fantôme |

```
export RDM_CV_TMP=<dossier temporaire>          # rendus intermédiaires (défaut /tmp/rdm_cv_bestiary)
flock "$BLENDER_LOCK" python3 art/blender/bestiary/carnival/build_cv_bestiary.py [--kinds cv_lost_clown,...]
... --preview s,se --anim idle:0,attack:3 --kinds cv_acrobat     # aperçu rapide
... --repack --kinds cv_lost_clown                               # atlas + méta depuis les images rendues
... --sheet                                                      # planche de présentation (captures)
```
Animations : idle (6), run (8), attack (6 : 0-2 élan, 2 tenue du télégraphe, 3 coup / lancer, 4-5
retour), hit (3), death (8, dernière image = cadavre ; ballons qui s'envolent, flammes éteintes,
cheval qui glisse au pied de sa barre) × 8 directions. Cadre 192 px ; Manège et élites 224 px ;
Grosse peluche 256 px. Boss : rendu 384 px stocké à 72 % (`world_per_px` compensé dans la méta),
idle 4 / run 6 / death 6 images (atlas mobile < 8192 px).
Sorties : `assets/sprites/enemies/<kind>/` (`_atlas.png` compression VRAM, `_frames.tres`, `_meta.json`).

### Refonte des modèles (31/10, branche `feature/refonte-bestiaires`)
Chaque modèle a été comparé à son illustration (colonne de gauche de la planche) et noté sur 6
critères (silhouette, palette, matières, accessoires, posture, lisibilité) ; tous étaient sous 7,5 et
ont été refaits jusqu'à ≥ 7,5 :
- **Clown égaré** : crâne chauve pâle, grosses touffes rousses, orbites noires, sourire plein de dents,
  collerette tricolore, veste grise sur gilet rayé rouge-orangé, mains griffues ensanglantées, ballons
  orange et noir, posture accroupie.
- **Acrobate sanguinaire** : bonnet de bouffon violet / rouge à grelots, masque blanc aux orbites
  noires, buste crème au losange rouge, manches prune, collants fauves, longue perche à faucille
  tenue à deux mains, garde basse jambes écartées.
- **Chien de cirque** : molosse-hyène gris tacheté, avant massif, caparaçon orangé (épaulières,
  poitrail, brassards), épines roses, oreilles en cornes, gueule béante pleine de crocs tournée vers
  le joueur (plus de chapeau ni de collerette).
- **Manège fantôme** : cheval de bois gris lavande à volutes claires, crinière sombre, bride dorée et
  rubans orangés, tête haute, avant cabré ; socle sombre à ampoules orangées.
- **Pénombre** : capuche pointue, visage noir aux yeux orangés, cape large en lambeaux, braises et
  boucle sur la poitrine, longue lame droite basse, ballons orange et rouge.
- **Grosse peluche** : fourrure brun-rouge usée, yeux pâles possédés sous des sourcils froncés,
  collerette à pétales fauves, cœur rouge cousu, bouton recousu sur la joue.
- **L'Être forain** : redingote de cuir noir longue à haut col, gilet orange incandescent, ruban
  orange lumineux sur le haut-de-forme, visage gris violacé fendu de fissures orangées.
- **Le Clown de feu** : chevelure de langues de feu (rouge / orange / jaune), visage blanc aux orbites
  noires, sourire carnassier, costume charbon semé de braises, boule de feu tenue en avant.
- **Le Roi du cirque** : visage blanc aux yeux rouges, couronne d'or, cheveux gris lavande, triple
  collerette blanche et violette, épaulières et plastron sombres bordés d'or, robe courte ouverte,
  sceptre à orbe sombre cerclé de feu, grande roue rouge-orangé.
Gabarits, cadres et données (`data/enemies/cv_*.tres`) inchangés. Aperçu d'évaluation :
`--hipreview s,se --anim idle:0 --kinds <kind>` (rendu ×2 conservé dans `RDM_CV_TMP`).

## Monstres communs (rangée 1 = plus simples, rangée 2 = plus durs)

| Kind | Nom | PV | Vitesse | Attaque | Compétences |
|---|---|---|---|---|---|
| `cv_lost_clown` | Clown égaré | 70 | 120 (moyenne) | griffe 11 (mêlée) | `cv_racket` (klaxon « HONK ! » : attire les créatures), `cv_balloon` (ballon rouge lent, 8) |
| `cv_acrobat` | Acrobate sanguinaire | 75 | 205 (rapide) | ruée + 2 coups de faucille (9) | `cv_vault` (salto **par-dessus le décor**, intouchable en vol, retombe derrière le joueur, attaque prête), `dodge_roll` |
| `cv_circus_dog` | Chien de cirque | 85 | 250 (très rapide) | morsure en ruée (12) | `cv_racket` (aboiement), `rush` (14) |
| `cv_ghost_carousel` | Manège fantôme | 190 | 108 | piétinement de zone 85 px (14) | `cv_waltz` (zone de musique : ralentit et brûle les joueurs, soigne les créatures, attire), `cv_call` (2 renforts clown / chien / acrobate) |
| `cv_penumbra` | Pénombre | 110 | 210 (rapide) | estoc 17 (télégraphe 0,3 s) | `cv_shade` (passif : quasi invisible et barre de vie masquée hors attaque), `cv_ambush` (surgit dans le dos / sur le flanc du joueur) |
| `cv_big_plush` | Grosse peluche | 380 | 95 (moyenne) | écrasement de zone 110 px (21) | `hard_skin` (rembourrage −25 % de tous côtés), `cv_vault` mode « on » (plongeon 100 px, 18, renverse) |

Comportements communs de la planche :
- **attirent les survivants par le bruit** : `cv_racket` (klaxon, aboiement : toutes les créatures
  dans 680 px accourent vers le joueur, un joueur caché tout près est débusqué), musique du manège
  (`cv_waltz` : alerte dans 620 px) ;
- **utilisent le décor du parc** : salto de l'acrobate par-dessus obstacles et structures, ombre de la
  Pénombre, manège sur sa barre, pièges de foire et feux du Roi ;
- **appellent d'autres créatures** : `cv_call` (Manège, Être forain, Roi du cirque).

## Élites (`elite = true`, `elite_kinds`)
| Kind | Nom | PV | Attaque | Compétences |
|---|---|---|---|---|
| `cv_fairground_being` | L'Être forain (maître de piste, mêlée / soutien) | 560 | canne : ruée + 3 coups (14), phase 2 sous 50 % | `cv_rally` (boniment : aura sur les créatures dans 420 px, −35 % de dégâts subis, vitesse ×1,2, +25 PV, 5 s), `cv_call` (2 renforts, max 4), `charge` (renverse) |
| `cv_fire_clown` | Le Clown de feu (zone / distance) | 500 | éventail de 3 boules de feu (12), garde ses distances, phase 2 sous 50 % | `molotov` (zone de feu), `fan_volley` (souffle de feu : 7 flammes à courte portée), `cv_fire_ring` (anneau de 10 foyers autour du joueur, 2 trous) |

## Boss : `cv_circus_king` — Le Roi du cirque, « Que la fête ne s'arrête jamais »
4400 PV, coup de sceptre de zone (150 px, 28), vitesse 100, pas d'étourdissement, invulnérable
1,2-1,5 s aux transitions.

| Phase | PV | Compétences | Entrée | Multiplicateurs |
|---|---|---|---|---|
| 1 — Le spectacle commence | 100 → 70 % | `cv_juggle` (3 torches en cloche → foyers), `cv_fire_ring`, `shockwave` | — | — |
| 2 — La parade des monstres | 70 → 30 % | `cv_call` (3 créatures, max 6 : clown, chien, acrobate, pénombre, peluche), `cv_fair_traps` (5 pièges à mâchoires autour du joueur), `teleport`, + phase 1 | parade | vitesse ×1,15, recharge ×0,85, dégâts ×1,15 |
| 3 — La fête éternelle | 30 → 0 % | `cv_fireworks` (3 salves de 5 feux d'artifice, la 1re fusée vise le joueur), `cv_waltz` (zone de musique 320 px autour de lui : contrôle), parade, pièges ×6, téléportation, + phase 1 | grand final | vitesse ×1,3, recharge ×0,6, dégâts ×1,45 |

## Compétences propres (`scripts/enemies/skills/carnival/`, déclarées dans `registry.gd`)
Valeurs par défaut lues dans `balance.cfg [bestiary_carnival]` (`cv_balance.gd`, clés
`<compétence>_<paramètre>`) ; les `.tres` ne remplacent que les réglages propres à un kind.
- `cv_racket` — vacarme (klaxon / aboiement) : créatures alertées vers le joueur, joueur caché débusqué.
- `cv_balloon` — ballon piégé (orbe rouge lent, hérite de `projectile_skill.gd`).
- `cv_vault` — saut de foire : « behind » (salto par-dessus le décor, intouchable, derrière le joueur)
  ou « on » (plongeon écrasant + statut).
- `cv_shade` (passif) — ombre : quasi invisible, barre de vie masquée hors attaque, révélée 1,6 s au coup.
- `cv_ambush` — surgit dans le dos / sur le flanc du joueur (hors de sa visée), attaque prête.
- `cv_call` — appel du parc (hérite du sifflet commun `whistle_skill.gd`).
- `cv_waltz` + `cv_music_zone.gd` — zone de musique qui suit son créateur (ralentit, petits dégâts,
  soigne les créatures, lumières de manège tournantes) ; disparaît à la mort du créateur.
- `cv_rally` + `cv_rallied` (passif temporaire posé sur les créatures) — boniment de l'Être forain.
- `cv_fire_ring` — anneau de foyers (`EnemyHazard` « fire ») autour du joueur, avec une sortie.
- `cv_juggle` — torches lancées en cloche (foyers).
- `cv_fair_traps` — pièges à mâchoires (`EnemyHazard` « trap » : root), au plus 10 vivants.
- `cv_fireworks` — salves de feux d'artifice (`EnemyHazard` « blast » après marquage au sol).
Compétences communes réutilisées : `dodge_roll`, `rush`, `charge`, `hard_skin`, `molotov`,
`fan_volley`, `shockwave`, `teleport`.

## Bestiaire (`data/bestiary/carnival.tres`)
- Rangée 1 (clown, acrobate, chien) : partout (clown seul à l'entrée, clown + peluche au repos).
- Rangée 2 (manège, pénombre, peluche) : combat, extraction, piège, trésor ; poids ×0,3 dans les
  salles calmes (fouille, couloir, repos) (`[bestiary_carnival] row2_kinds`, `row2_shallow_mult`).
- Pénombres et manèges en salle piège, manège / peluche / pénombre en salle au trésor.
- `elite_kinds = [cv_fairground_being, cv_fire_clown]`, `boss_kind = cv_circus_king`.

## Changements partagés
Aucun fichier partagé modifié (hors section `[bestiary_carnival]` de `balance.cfg`). Points
d'attention pour le chef de projet :
- Le script Blender importe `art/blender/bestiary/mall/build_mall_bestiary.py` (classes `Rig`,
  `Human`, rendu) : une modification de ce fichier peut changer les rendus du carnaval.
- Coop : la zone de musique (`cv_music_zone.gd`) et l'aura du forain sont locales à l'hôte (pas de
  copie visuelle chez l'invité, comme la tornade du Far West) ; l'opacité de la Pénombre
  (`set_modulate`) n'est pas relayée (même remarque que la Nuit blanche du centre commercial).
- Butin : seule table propre `data/loot_tables/enemy_cv_circus_king.tres` (exigée pour chaque boss
  par `tests/test_boss_loot.gd` ; 4-6 objets, jamais vide, Épiques et Légendaires possibles). Objets
  génériques (pas encore d'objets du carnaval) calqués sur la table de l'Omnistore. Les autres
  cv_* retomberont sur la table du biome quand le monde existera.

## Tests
`tests/test_bestiary_carnival.gd` : données, planches, noms et caractéristiques de la planche,
compétences connues, valeurs dans balance.cfg, bestiaire, effets de chaque compétence, élites, boss
(phases, transitions, parade, pièges, feux d'artifice).

Suite complète (30/10) : 722 tests, 717 OK ; restent 3 tests de chronométrage hors périmètre
(`test_mall.gd`, `test_raid.gd`, `test_space_station.gd` : génération d'étage > 50 ms sur cette
machine lente) ; l'échec `test_boss_loot` (table du Roi du cirque) est corrigé.

## Captures (`docs/bestiaire/captures/carnival/`)
Arène de test dans un raid de Dust Creek (pas de carte du carnaval), brouillard levé, HUD caché.
- `planche_modeles_carnival.png` — les 9 modèles (idle, attaque, cadavre).
- `en_jeu_classiques_repos.png`, `en_jeu_classiques_combat_{0,1,2}.png` — les 6 communs.
- `competences_telegraphes.png`, `competences_effets.png`, `competences_valse.png` — klaxon, salto,
  plongeon, valse du manège, ballon.
- `en_jeu_elites_repos.png`, `en_jeu_elites_combat_{0,1,2}.png`, `elites_telegraphes.png`,
  `elites_cercle_de_feu_boniment.png` — élites et leurs compétences.
- `boss_phase1.png`, `boss_phase1_jonglage.png`, `boss_phase2_parade.png`, `boss_phase2_pieges.png`,
  `boss_phase3_grand_final.png`, `boss_phase3_feux.png` — les 3 phases du Roi du cirque.
