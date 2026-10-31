# Difficulté des 6 mondes : 600 parties du bot (31/10/2026)

**Protocole.** `python3 tools/playtest/run_campaign.py --pass mondes` : 100 parties par carte,
seeds 12000+ (rejouables), sur la branche `feature/refonte-bestiaires` (commit 50825896).
- 75 raids : 5 difficultés × 3 profils (prudent, agressif, fouilleur) × 5 tours, 420 s de jeu au plus.
- 25 combats de boss : départ à l'entrée de l'arène, Normal et Difficile × 3 arsenaux (débutant, moyen, équipé).
- Bot sans triche, mais **plus faible qu'un bon joueur humain** (voir `tools/playtest/README.md`). Il faut lire les
  chiffres comme une comparaison entre mondes, pas comme un taux de victoire absolu.
- 600 parties sur 600 jouées, 0 plantage. 3 combats contre l'Omnistore invalides (le boss disparaît
  de la liste sans mourir, bug déjà connu).

## Raids : taux d'extraction (15 raids par case)

| Monde | Facile | Normal | Difficile | Expert | Cauchemar | Total | Kills (médiane) |
|---|---|---|---|---|---|---|---|
| Far West (Dust Creek) | 14 | 10 | 10 | 7 | 6 | **63 %** | 23 |
| Station Kagami | 15 | 12 | 13 | 13 | 9 | 83 % | 34 |
| Galeries Lumière | 13 | 9 | 10 | 12 | 9 | 71 % (18 raids à court de temps) | 33 |
| Carnaval hanté | 12 | 6 | 12 | 14 | 13 | 76 % | 22 |
| **Terres gelées** | **0** | **0** | **0** | **0** | **0** | **0 %** | **57** |
| Pyramides d'Égypte | 15 | 12 | 14 | 11 | 8 | 80 % | 29 |

**Principaux tueurs en raid :**
- Terres gelées : `ice_wolf` (44 morts sur 60).
- Far West : `fw_bandit` (12) et `fw_sharpshooter` (11).
- Carnaval : le boss `cv_circus_king` croisé pendant le raid (8).

## Combats de boss : 1 victoire sur 147

| Boss (PV de base) | PV du boss à la mort du bot, médiane (débutant / moyen / équipé) | Durée | Ce qui fait le plus de dégâts |
|---|---|---|---|
| Shérif (3000) | 0,92 / 0,40 / 0,50 | 37 s | le boss 82, `fw_buffalo` 50 |
| Architecte (3000) | 0,64 / 0,53 / 0,23 | 43 s | le boss 101 |
| Omnistore (3200) | 0,80 / 0,70 / 0,63 | 30 s | le boss 77, `mall_violent` 66 |
| Roi du cirque (4400) | 0,93 / 0,80 / 0,83 | 28 s | le boss 38, `cv_fairground_being` 27 |
| Titan de glace (4200) | 0,98 / 0,91 / 0,70 | 24 s | `ice_wolf` 36, le boss 30 |
| Pharaon (4200) | 0,98 / 0,89 / 0,98 | **15 s** | `eg_shadow_warrior` 45, le boss 29 |

Les dégâts de la colonne de droite sont les PV perdus par combat (le joueur a 100 PV).

## Constats

1. **Bug de la meute des Terres gelées : les renforts sifflent à leur tour, sans fin.**
   - Le loup a la compétence `whistle` (`chance` 0,5, `initial_cooldown` 1,5 s, `max_total` 2 par chef).
   - `Enemy.spawn_reinforcement()` marque le renfort (`meta "reinforcement"`), mais rien ne lit ce
     marqueur. Chaque loup appelé peut donc siffler 1,5 s après son arrivée.
   - Résultat : 59 loups tués par raid en 2 minutes, 0 extraction. Le Titan en souffre aussi
     (le loup est le premier tueur dans son arène).
2. **Les boss des mondes 4 à 6 sont bien plus durs que ceux des mondes 1 à 3.**
   - PV : 4200-4400 au lieu de 3000-3200.
   - Coup de base : 28-30 au lieu de 10-26.
   - Avec l'arsenal équipé, le bot ne leur retire que 2 à 30 % de leurs PV.
3. **L'escorte du Pharaon tue le joueur avant le boss.** Le Guerrier de l'ombre (560 PV, vitesse 168)
   tue en 15 s. Même schéma qu'au Far West (Buffle) et au Centre commercial (Violent).
4. **Far West : c'est le monde le plus dur en raid** (63 %), à cause des tireurs. `fw_sharpshooter`
   inflige 22 dégâts par tir, soit 22 % des PV du joueur.
5. **Galeries Lumière : 18 raids à court de temps.** C'est la longueur de la carte (raid médian
   274 s), pas la difficulté : le bot y meurt très peu (4 morts).

## Ajustements proposés (non appliqués)

| # | Fichier, clef | Avant | Après | Effet attendu |
|---|---|---|---|---|
| 1 | `scripts/enemies/skills/whistle_skill.gd` : `can_use_extra()` renvoie `false` si `e.has_meta(&"reinforcement")` (correction de bug, 1 ligne + 1 test GUT) | renforts qui sifflent | renforts muets | Termine la réaction en chaîne, sur tous les mondes (`fw_bandit` siffle aussi) |
| 2 | `data/enemies/ice_wolf.tres`, `skills` → `whistle` | `chance` 0,5 · `initial_cooldown` 1,5 · `max_total` 2 | 0,3 · 6,0 · 1 | La meute appelle moins et plus tard |
| 3 | `data/balance.cfg [bestiary_frozen]` `pack_damage_per_ally` | 0,12 | 0,08 | Meute de 4 : +24 % de dégâts au lieu de +36 % |
| 4 | `data/enemies/cv_circus_king.tres` `max_hp` | 4400 | 3400 | Aligné sur les boss 1-3 (+6 % au plus) |
| 5 | `data/enemies/ice_titan.tres` `max_hp` | 4200 | 3300 | idem |
| 6 | `data/enemies/eg_pharaoh.tres` `max_hp` | 4200 | 3300 | idem |
| 7 | `attack_damage` de `cv_circus_king`, `ice_titan`, `eg_pharaoh` | 28 / 30 / 28 | 22 / 22 / 22 | Coup de base proche de l'Omnistore (26) et en dessous |
| 8 | `data/balance.cfg [boss] elite_boss_escorts` | [0, 1, 1, 1, 2] | [0, 0, 1, 1, 2] | Pas d'élite d'escorte en Normal : on affronte le boss, pas l'escorte |
| 9 | `data/enemies/eg_shadow_warrior.tres` `move_speed` | 168 | 150 | Escorte du Pharaon aussi rapide que l'Être forain |
| 10 | `data/enemies/fw_sharpshooter.tres` `attack_damage` | 22 | 18 | Far West plus proche des autres mondes (~70 %) |

**Ordre conseillé :**
1. Appliquer d'abord **1 à 3**, puis rejouer seulement les Terres gelées
   (`--only gelees`, 100 parties, environ 15 min) pour viser 60-80 % d'extraction.
2. Appliquer ensuite **4 à 9**, puis rejouer la passe boss.
3. Le 10 est optionnel.

Je n'ai rien changé à l'équilibrage sans ta validation.

## Reproduire
```bash
python3 tools/playtest/run_campaign.py --root ~/.cache/maskit/campagne_mondes --pass mondes --jobs 8 --max-jobs 8
```
Journaux JSON : `~/.cache/maskit/campagne_mondes/mondes/` (hors dépôt). Sur macOS, chaque partie a
son propre `HOME`, ce qui protège la sauvegarde ; CloudSync est coupé en headless.

## Après application des réglages 1 à 10 (mêmes 600 seeds)

| Monde | Extraction avant → après | Victoires boss avant → après | PV du boss restants, arsenal équipé (médiane) |
|---|---|---|---|
| Far West | 63 % → **72 %** | 1 → **6** / 25 | 0,50 → 0,12 |
| Station Kagami | 83 % → 83 % | 0 → 0 / 25 | 0,23 → 0,03 |
| Galeries Lumière | 71 % → 59 % (*) | 0 → 0 | 0,63 → 0,53 |
| Carnaval hanté | 76 % → 73 % | 0 → 0 | 0,83 → 0,73 |
| Terres gelées | **0 % → 28 %** | 0 → 0 | 0,70 → 0,38 |
| Pyramides d'Égypte | 80 % → **85 %** | 0 → 0 | 0,98 → 0,86 |

(*) Aucun réglage ne touche les raids des Galeries : l'écart vient des seeds et des raids qui manquent de temps sur cette longue carte.

**Lecture :**
- **Bug du sifflet :** il est corrigé. Aux Terres gelées, le bot tue maintenant 44 ennemis par raid, contre 57 avant.
- **Terres gelées :** elles restent le monde le plus dur, à 28 % d'extraction. Le nouveau premier tueur en raid est le Titan de glace (20 morts sur 54) : le bot le croise pendant le raid.
- **Boss :** ils sont nettement plus entamés, mais seul le Shérif est battu (6 victoires). Pour la Station, l'arsenal équipé laisse l'Architecte à 3 % de PV.

**Pistes pour une 2e passe (non appliquées) :**
- **Titan de glace :** l'éloigner du chemin du raid, ou baisser sa détection de 800 → 500 px.
- **Terres gelées :** ajuster la densité de loups.
