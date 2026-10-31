# Boss par rareté d'arsenal : 240 combats du bot (31/10/2026)

**Protocole.** `python3 tools/playtest/run_campaign.py --pass boss_rarete` : 6 boss × 4 arsenaux × 10 combats,
seeds 13000+ (rejouables), branche `fix/equilibrage-mondes` (réglages 1 à 10 appliqués).
- Mode boss : départ à l'entrée de l'arène, avec l'escorte. Difficulté **Normal**, profil agressif, 480 s au plus.
- Soins de départ (~75 PV d'objets du biome). **Correction :** les mondes 4 à 6 n'en avaient pas jusqu'ici, ce qui
  biaisait la campagne précédente contre leurs boss. Les kits ajoutés :
  - Carnaval : 2 pommes d'amour ;
  - Terres gelées : 3 thermos ;
  - Pyramides : 2 outres d'eau et 1 pot de miel.
- 240 combats sur 240 joués, 0 plantage. 3 combats contre l'Omnistore sont invalides (le boss disparaît sans mourir,
  bug déjà connu).
- Le bot ne triche pas, mais il est **plus faible qu'un bon joueur humain**. Il faut lire ces chiffres comme une
  borne basse.

| Arsenal | Armes | Gadget |
|---|---|---|
| Commun | AK-47, M24, MP5 | grenade |
| Rare | M4A1, AX50, Vector | grenade (le seul gadget Rare est le fumigène) |
| Épique | SCAR-H, M82, P90 | C4 |
| Légendaire | AUG, P320, Uzi (pas de sniper Légendaire) | drone |

## Résultat : boss battus sur 10

Entre parenthèses : PV restants du boss (médiane) quand il n'est pas battu.

| Boss (monde) | Commun | Rare | Épique | Légendaire | Durée du combat gagné (médiane, Épique / Légendaire) |
|---|---|---|---|---|---|
| Shérif (Far West) | **8** | 3 (22 %) | **10** | **10** | 28 s / 20 s |
| Architecte (Station Kagami) | 5 | 7 | 8 | **10** | 30 s / 20 s |
| Omnistore (Galeries Lumière) | 0 (62 %) | 0 (57 %) | 5 | 7 | 33 s / 26 s |
| Roi du cirque (Carnaval hanté) | 0 (55 %) | 0 (61 %) | 3 (13 %) | 8 | 49 s / 27 s |
| Titan de glace (Terres gelées) | 0 (29 %) | 1 (30 %) | 5 | **10** | 36 s / 20 s |
| Pharaon (Pyramides) | 0 (60 %) | 0 (61 %) | **1** (22 %) | 7 | 85 s / 40 s |
| **Total** | **13 / 60** | **11 / 60** | **32 / 60** | **52 / 60** | |

Tous les boss sont battables : avec l'arsenal Légendaire, le bot gagne 7 à 10 combats sur 10 contre chacun.

## Constats

1. **La progression par rareté marche, sauf entre Commun et Rare.**
   - Les taux de victoire par arsenal : Commun 22 %, Rare 18 %, Épique 53 %, Légendaire 87 %.
   - L'arsenal Rare ne fait pas mieux que le Commun. Au Far West, il fait même moins bien (3 victoires contre 8).
     Sur 10 combats, une partie de l'écart peut venir du hasard. Il faut quand même vérifier le trio M4A1 / AX50 /
     Vector face à l'AK-47 / M24 / MP5.
2. **Deux paliers de boss.**
   - **Mondes 1-2** (Shérif, Architecte) : le bot les bat déjà en Commun, et presque toujours dès l'Épique.
   - **Mondes 3-6** : sans arme Épique, le bot ne les bat jamais (1 victoire en 80 combats Commun et Rare). Le boss
     garde alors 30 à 60 % de ses PV.
3. **Le Pharaon est le plus dur.**
   - En Épique : 1 victoire sur 10, et le combat gagné a duré 85 s.
   - En Légendaire : 7 victoires sur 10, en 40 s (deux fois plus long que les autres boss).
   - Le Roi du cirque suit, avec 3 victoires sur 10 en Épique.
4. **Ce qui tue le bot.**
   - Le boss lui-même, dans 70 à 120 PV de dégâts par combat. La mort survient surtout en phase 2 (Commun, Rare)
     ou en phase 3 (Épique).
   - Les escortes pèsent moins qu'avant le réglage 8, sauf deux : les chiens et acrobates du Carnaval
     (~40 PV par combat en Commun et Rare), et les archers et momies des Pyramides (~35 PV).
5. **Après la mort du boss, l'arène reste dangereuse.**
   - Le bot continue tant qu'une élite est en vie.
   - Aux Terres gelées en Légendaire, il bat le Titan 10 fois sur 10 et meurt ensuite 10 fois sur 10, environ 56 s
     plus tard, face aux élites du même étage (Élémentaire, Gardien du glacier).
   - Ces morts ne sont pas comptées comme des défaites contre le boss.
6. **Bugs vus pendant la campagne.**
   - **Omnistore** : il disparaît sans mourir dans 3 combats (déjà connu).
   - **`player.gd:1138`** (`damage_source_name`), 4 fois : « Left operand of 'is' is a previously freed instance ».
     La source d'un dégât a été libérée avant la lecture, et le test `v is Enemy` est fait avant
     `is_instance_valid(v)`.

## Pistes (non appliquées)

Tout dépend de la courbe visée. Exemple : « Épique ≈ 50 % de victoires du bot sur chaque boss ».
- **Pharaon :** PV 3300 → ~2800, ou dégâts de phase 3 en baisse.
- **Roi du cirque :** une baisse plus légère (PV 3400 → ~3000).
- **Rare vs Commun :** comparer les armes Rare et Commune au stand de tir (`tools/weapon_capture`) avant d'y toucher.
- **Terres gelées :** moins d'élites autour de l'arène du Titan.

## Reproduire
```bash
python3 tools/playtest/run_campaign.py --root ~/.cache/maskit/campagne_boss_rarete --pass boss_rarete --jobs 8 --max-jobs 8
```
La passe dure environ 20 minutes sur 8 cœurs. Les journaux JSON sont dans `~/.cache/maskit/campagne_boss_rarete/boss_rarete/`.
