# Raids plus durs dans les derniers mondes (31/10/2026)

**Demande de Victor :** durcir les raids des derniers mondes sans rendre leurs boss infaisables
(option 1 : on garde les objectifs de l'escalier pour les boss).

**Mesure.** Bot sans triche, plus faible qu'un bon joueur humain. Chaque monde est joué à la difficulté
de sa carte, avec l'arsenal attendu :
- passe `raids` (nouvelle) : 30 raids par monde, 3 profils × 10, seeds 15000+ ;
- passe `escalier` : 20 combats de boss par arsenal.

## Résultat

| Monde | Extraction des raids, avant → après | Boss battu (objectif) avant → après |
|---|---|---|
| 4 Carnaval (Rare) | 93 % → **83 %** | Rare 5 → 10 % (20), Épique 45 → **50 %** (45) |
| 5 Terres gelées (Épique) | 90 % → **83 %** | Épique 40 → **45 %** (35) |
| 6 Pyramides (Épique) | 100 % → **93 %** | Épique 5 → 10 % (25), Légendaire 60 → **55 %** (60) |

Les mondes 1 à 3 ne changent pas : tous leurs multiplicateurs valent 1.

**Lecture :**
- Les raids des mondes 4 à 6 sont plus peuplés : +30 % d'ennemis au Carnaval, +35 % aux Terres
  gelées, +45 % aux Pyramides. Leurs ennemis frappent aussi plus fort.
- Les boss restent dans leurs objectifs, à ±10 points de bruit sur 20 combats.
- Les Pyramides restent le monde où le bot extrait le plus (93 %). Le pousser plus bas faisait
  aussi tomber le Pharaon : à 1,35 de dégâts et ×1,5 d'ennemis, il tombait à 5 % en Légendaire,
  parce que le bot mourait avant d'arriver dans l'arène.
- Le bot extrait facilement, parce qu'il se soigne et quitte le raid tôt. Un joueur qui fouille tout
  restera plus longtemps exposé.

## Ce qui change

### Code
- **`[world_scaling]` sépare deux courbes.**
  - Les **ennemis du raid** suivent `hp_mult`, `damage_mult` et le nouveau `enemy_density_mult`.
  - Le **boss et les ennemis de sa salle** (escorte, gardes, renforts qu'ils appellent) suivent les
    nouvelles clés `boss_hp_mult` et `boss_damage_mult`.
  - On règle donc les raids sans toucher aux combats de boss.
  - Dans le code : `Enemy._world_key()` et la meta `Enemy.META_BOSS_ARENA`. Le Raid la pose sur les
    ennemis nés dans la salle du boss et la garde quand on change d'étage ; les renforts du boss en
    héritent.
- **`enemy_density_mult`** s'ajoute au multiplicateur de densité de la carte (`Raid._apply_map_modifiers`).
- **`Raid.scale_enemy_spawns`** n'ajoute plus jamais d'ennemi dans la salle du boss : avant, il pouvait
  dupliquer le boss ou ses gardes.

### Valeurs (`data/balance.cfg [world_scaling]`, mondes 4 / 5 / 6, avant → après)

| Clé | Carnaval | Terres gelées | Pyramides |
|---|---|---|---|
| `hp_mult` (ennemis du raid) | 0,6 → 1,0 | 0,6 → 1,15 | 0,85 → 1,1 |
| `damage_mult` (ennemis du raid) | 0,7 → 1,1 | 0,85 → 1,2 | 0,65 → 1,25 |
| `enemy_density_mult` (nouveau) | 1,3 | 1,35 | 1,45 |
| `boss_hp_mult` (nouveau ; avant : `hp_mult`) | 0,6 → 0,5 | 0,6 → 0,55 | 0,85 → 0,6 |
| `boss_damage_mult` (nouveau ; avant : `damage_mult`) | 0,7 → 0,6 | 0,85 → 0,75 | 0,65 → 0,55 |

Mondes 1 à 3 : `boss_*` égaux aux anciennes valeurs, densité 1.

## Reproduire
```bash
python3 tools/playtest/run_campaign.py --root ~/.cache/maskit/raids --pass raids --jobs 8 --max-jobs 8
python3 tools/playtest/run_campaign.py --root ~/.cache/maskit/raids --pass escalier --only boss_ --jobs 8 --max-jobs 8
```
