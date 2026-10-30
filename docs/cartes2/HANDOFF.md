# Passation : trois nouvelles cartes + bestiaires (branche `feature/cartes-carnaval-glace-egypte`)

Mis à jour le 30/10/2026 ~20 h 30. À relire avec `docs/cartes2/CONTRAT.md` (règles, propriété des
fichiers, verrous) et les journaux par carte `docs/cartes2/{haunted_carnival,frozen_lands,egypt_pyramids}.md`.

## Demande de l'utilisateur
1. Créer les 3 cartes de `docs/reference/cartes_2.png` (Carnaval hanté, Terres gelées, Pyramides
   d'Égypte) avec la même démarche que Dust Creek / Station Kagami / Galeries Lumière (générateur →
   `export_layout.gd` → scène Blender pré-rendue → `compose.py` → paquet 72 px/case → mini-carte → jeu).
2. **Similitude ≥ 75 % (7,5/10) avec la planche**, évaluée honnêtement (`compare_N.png`). Pour le
   **Carnaval : « la plus belle carte du jeu »**, viser 8,5.
3. Ensuite (phase 2) : bestiaire propre à chaque monde d'après `docs/reference/bestiaire_cartes_2.png`
   (6 communs, 2 élites, 1 boss par monde = 27 monstres), modélisés sous Blender comme le bestiaire
   existant (`docs/bestiaire/CONTRAT.md`), puis branchés dans les rosters à la place des rosters
   provisoires (Carnaval → `mall_*`, Terres gelées → `ss_*`, Pyramides → `fw_*`).
4. Git (CLAUDE.md) : jamais de push sur `main` ; PR avec description précise + captures sur la branche
   `pr-assets` ; ne jamais fusionner soi-même.

## Environnement (à réinstaller dans un nouveau conteneur)
- Godot 4.7.2 : `Godot_v4.7.2-stable_linux.x86_64.zip` depuis les releases GitHub → `/usr/local/bin/godot`.
- Blender en module : `pip install --break-system-packages bpy` (5.2.3), Cycles CPU.
- Machine à 2 cœurs : tout rendu sous `flock /home/claude/.blender_render.lock`, tout Godot sous
  `flock /home/claude/.godot.lock`. Itérer à ppc 12 / 4 samples (~1 min), final 72 px/case.

## État par carte
| Carte | Biome / id | État | Note honnête | Reste à faire |
|---|---|---|---|---|
| Carnaval hanté | `haunted_carnival`, `perm_carnaval_hante`, seed 2025 | Plan refait « organique » (31 bâtiments, place centrale), itération 17 ≈ 7,1/10. Paquet 72 px/case présent dans `assets/prerender/haunted_carnival/2025/` mais **issu de l'ANCIEN plan** → à re-rendre | 7,1 | Modélisation dans `hc_scene.py` : enceinte de pierre/gradins autour du chapiteau, tête de clown d'entrée 2-3× plus grande et sculptée (violet, pas blanc), bâtiments à toits en pente/enseignes, roulottes lisibles, encombrement au sol. Puis final (`hc_pipeline.sh 2025 <work> 72 10`, puis `hc_grade.py`), mini-carte, captures, tests. Supprimer `tools/prerender/_hc_check.gd`, `_hc_prof.gd` |
| Terres gelées | `frozen_lands`, `perm_terres_gelees`, seed 12345 | Plan refait en croix compacte (itération 13 ≈ 7,7/10). **Rendu final 72 px/case en cours** (passes full/mask/occ faites, intérieurs par lots via `tools/prerender/fl_final_batches.sh`) | 7,7 | Fin des intérieurs, compose, mini-carte, captures, tests, ajout de `perm_terres_gelees` à `[maps] only_ids` |
| Pyramides d'Égypte | `egypt_pyramids`, `perm_pyramides_egypte`, seed 2026 | Itération 29 ≈ 7,2–7,45/10 (murs en ruine, intérieurs meublés, sphinx, pyramides à gradins). Étalonnage `tools/prerender/eg_grade.py` intégré à `eg_pipeline.sh`. Feu vert donné pour le final après 2 corrections d'étalonnage (halos de torches plus petits, sable plus ocre/contrasté) | ~7,3 | Corrections d'étalonnage, final `eg_pipeline.sh 2026 <work> 72 16 6`, mini-carte, captures, vignette, tests, `only_ids` |

Les scripts d'aperçu/capture de chaque carte : `tools/prerender/{hc,fl,eg}_*`. Captures et comparaisons
de travail (hors dépôt) : `/tmp/claude-0/-home-claude/e0bdc8a1-40bd-55ff-aaa7-e9333f948c56/scratchpad/shots/{carnival,frozen,egypt}/`
(perdues si le conteneur est recréé : re-générer avec les scripts de capture).

## Fichiers partagés NON committés (volontairement)
`scripts/biomes/biome_registry.gd` (enregistre les 3 biomes), `data/balance.cfg` (sections
`[haunted_carnival]`, `[frozen_lands]`, `[egypt_pyramids]`, `[bestiary_egypt_pyramids]`, et
`perm_carnaval_hante` dans `only_ids`), `assets/ui/maps/build_map_thumbs.py` (3 vignettes). À
committer au **commit d'intégration**, quand les trois paquets finaux sont livrés et la suite verte.
⚠ `perm_carnaval_hante` est déjà dans `only_ids` alors que son paquet doit être re-rendu : le retirer
si on intègre avant le nouveau rendu.

## Tests connus en échec (dernière suite complète : 704 tests, 691 OK, 11 KO)
- Paquets pré-rendus absents ou périmés (Pyramides pas encore rendu, Terres gelées 12345 ancien plan,
  Carnaval ancien plan) → disparaissent avec les rendus finaux.
- Mall : paquet du dépôt à 24 px/case < 72 (préexistant, hors périmètre).
- Perf génération < 50 ms/étage : échoue quand Blender tourne (machine chargée) ; à relancer à vide.
- `eg_pharaoh_mask` renommé `eg_pharaoh_scepter` (règle « plus de masques ») : vérifier qu'il n'en
  reste aucune référence.

## Étapes finales (intégration + PR)
1. `flock /home/claude/.godot.lock godot --headless --path . --import` puis `--quit` (aucune erreur).
2. Suite GUT complète à vide : `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
3. Commit des fichiers partagés + `only_ids` avec les 3 ids ; push de la branche.
4. Captures (`M_overview`, `M_ingame_1..3`, `compare_final`) de chaque carte poussées sur `pr-assets`
   dans `feature-cartes-carnaval-glace-egypte/`, PR vers `main` avec description complète
   (fonctionnalités, fichiers, sections de balance.cfg ajoutées, notes de similitude, tests).
5. Phase 2 bestiaires : 1 agent par monde, contrat calqué sur `docs/bestiaire/CONTRAT.md`
   (ids `hc_*`, `fl_*`, `eg_*`), branche dédiée `feature/bestiaires-carnaval-glace-egypte` créée après
   la PR des cartes.
