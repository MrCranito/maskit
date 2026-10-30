# Campagne de nuit du 30/10 (tour Windows, i7-10700KF, 12 parties en parallèle)

Code joué : `chore/playtest-auto` @ f487f3b. Nouvelles seeds, distinctes des passes A/B/boss/duel.
- `nuit_raid` : 2700 raids, 60 tours × 3 cartes × 5 difficultés × 3 profils (seeds 20000+).
- `nuit_boss` : 1080 combats, 60 tours × 3 boss × 2 difficultés × 3 tiers (seeds 30000+).
- `nuit_duel` : 720 duels, 60 tours × 6 élites × 2 tiers (seeds 40000+).
0 échec technique. Lanceur hors dépôt réutilisant `run_campaign.run_job`.

## Extraction par carte et difficulté (raids, n=180 par case)
| Carte | Facile | Normal | Difficile | Expert | Cauchemar |
|---|---|---|---|---|---|
| Dust Creek | 35 % | 6 % | 0 % | 0 % | 0 % |
| Station Kagami | 57 % | 8 % | 0 % | 0 % | 0 % |
| Galeries Lumière | 67 % | 20 % | 1 % | 0 % | 0 % |

Principaux tueurs : ss_teleporter 449, fw_raider 284, fw_marauder (hyène) 273, mall_flayer 271.

## Boss (360 combats chacun) : 0 victoire
Boss blessé : Shérif 4, Architecte 94, Omnistore 48.

## Duels : victoire du bot (moyen / équipé)
fw_buffalo 17/68 %, fw_deserter 27/67 %, mall_store_warden 0/17 %, mall_violent 35/88 %, ss_atlas 73/95 %, ss_drone_tieur 100/100 %.

## Erreurs Godot relevées
- `texture_storage.h:85 Parameter "t" is null` : 356 raids, 15 duels.
- `rid_owner.h` (RID nul / déjà initialisé) : ~34 raids.
- `raid.gd:477 Cannot call method 'get' on a null value` : 6 combats de boss (bug de script à corriger).
