# Escalier de difficulté des 6 mondes (31/10/2026)

**Objectif (Victor) :** un jeu dur, mais pas infaisable dans les premiers mondes, qui se corse ensuite.
Option choisie : **A puis B**.
- **A** fixe un escalier par monde : difficulté de la carte et arsenal attendu, puis réglage des boss.
- **B** ajoute des multiplicateurs par monde dans `balance.cfg`. La courbe se règle à un seul endroit.

**Mesure.** Nouvelle passe `python3 tools/playtest/run_campaign.py --pass escalier` (288 parties) :
- chaque monde est joué **à la difficulté de sa carte**, comme dans le jeu (`--difficulty=-1`) ;
- le bot porte l'arsenal attendu à ce stade ;
- 20 combats de boss par arsenal, plus 18 raids par monde (3 profils × 6), seeds 14000+ ;
- 6 campagnes de réglage ont précédé la vérification finale.

Le bot est plus faible qu'un bon joueur humain : ses taux de victoire sont une borne basse.

## Résultat : victoires du bot contre le boss

| Monde | Carte | Arsenal | Objectif | Départ (v0) | **Final** |
|---|---|---|---|---|---|
| 1 Far West | Facile | Commun | 60 % | 100 % | **60 %** |
| 2 Station | Normal | Commun / Rare | 45 % | 40 / 65 % | **35 / 55 %** |
| 3 Galeries | Normal | Rare | 40 % | 0 % | **25 %** |
| 4 Carnaval | Difficile | Rare / Épique | 20 / 45 % | 0 / 0 % | **5 / 45 %** |
| 5 Terres gelées | Normal → **Difficile** | Épique | 35 % | 85 % (en Normal) | **40 %** |
| 6 Pyramides | Difficile → **Infernal** | Épique / Légendaire | 25 / 60 % | 0 / 5 % (en Difficile) | **5 / 60 %** |

Sur 20 combats, le bruit est d'environ ±10 points : d'une campagne à l'autre, le même réglage a donné 40 à 70 %
au Far West.

**Lecture :**
- **Les objectifs atteints :** monde 1, monde 2 (45 % en moyenne), monde 5, l'Épique au monde 4 et le
  Légendaire au monde 6.
- **Encore sous l'objectif :**
  - l'Omnistore en Rare (25 %, objectif 40 %) ;
  - le Roi du cirque en Rare (5 %) ;
  - le Pharaon en Épique (5 %).
  Ces trois boss demandent l'arsenal de la rareté suivante, ce qui reste cohérent avec « ça se corse ».

## Raids : taux d'extraction (18 raids par monde)

| Far West | Station | Galeries | Carnaval | Terres gelées | Pyramides |
|---|---|---|---|---|---|
| 100 → 100 % | 100 → 89 % | 94 → 83 % | 28 → **83 %** | 94 → 83 % | 83 → 100 % |

Le Carnaval n'est plus le mur qu'il était (28 %). Mais **les raids ne suivent pas encore l'escalier** : le bot,
avec l'arsenal attendu, extrait 83 à 100 % du temps partout. C'est la prochaine passe à faire si on veut
des raids plus durs dans les derniers mondes.

## Ce qui change (avant → après)

**Option A**
| Fichier | Clef | Avant | Après |
|---|---|---|---|
| `data/maps/perm_terres_gelees.tres` | `difficulty` | 1 (Normal, défaut) | 2 (Difficile) |
| `data/maps/perm_pyramides_egypte.tres` | `difficulty` | 2 (Difficile) | 3 (Infernal) |
| `data/enemies/mall_omnistore.tres` | `max_hp` | 3200 | 1400 |
| | `attack_damage` | 26 | 22 |
| | `mall_alarm` (phases 2 et 3) : `count` / `max_total` | 3 / 7 | 2 / 5 |
| `data/enemies/eg_pharaoh.tres` | `max_hp` | 3300 | 1500 |
| | `attack_damage` | 22 | 18 |
| `data/weapons/smg_vector.tres` | `inaccuracy_deg` | 2,2 | 1,6 |
| | `spread_bloom_max` | 6,5 | 6,0 |

**Le Vector** expliquait l'arsenal Rare plus faible que le Commun : 144 dégâts/s sur le papier, mais une balle
sur deux ratée (3,6 dégâts par tir contre 7,1 pour l'AK-47).

**Option B : nouvelle section `[world_scaling]` de `data/balance.cfg`**
- Elle multiplie les PV et les dégâts de **tous** les ennemis et tourelles du monde, boss compris.
- Elle s'ajoute à la difficulté de la carte et à ses modificateurs.
- Code : `Enemy.world_mult()` et `Enemy.hp_scale()` dans `scripts/enemies/enemy.gd`, branchés aussi dans
  `scripts/enemies/turret.gd`.

| Monde | `hp_mult` | `damage_mult` |
|---|---|---|
| world_01_far_west | 1,3 | 1,3 |
| world_02_space_station | 1,05 | 1,15 |
| world_03_mall | 1,0 | 1,0 |
| world_04_haunted_carnival | 0,6 | 0,7 |
| world_05_frozen_lands | 0,6 | 0,85 |
| world_06_egypt_pyramids | 0,85 | 0,65 |

Les mondes 4 à 6 ont des multiplicateurs inférieurs à 1 : ils **compensent** la difficulté de leur carte
(Difficile, Infernal). La montée vient de la carte :
- dégâts et vitesse des ennemis ;
- élite d'escorte du boss ;
- PV du boss ×1,5 à ×2 ;
- butin plus rare.

Le multiplicateur règle la marche exacte.

## Reproduire
```bash
python3 tools/playtest/run_campaign.py --root ~/.cache/maskit/escalier --pass escalier --jobs 8 --max-jobs 8
```
La passe dure environ 20 minutes sur 8 cœurs.
