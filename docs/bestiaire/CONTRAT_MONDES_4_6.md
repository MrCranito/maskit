# Bestiaires des mondes 4 à 6 (branche `feature/bestiaire-mondes-4-6`)

Planche de référence : `docs/reference/bestiaire_mondes_4_6.png` (3 colonnes).
Par monde : **6 monstres communs** (rangée 1 = plus simples, rangée 2 = plus durs), **2 élites**,
**1 boss** en 3 phases, vraiment très difficile. Même contrat technique que
`docs/bestiaire/CONTRAT.md` (lis-le), avec ces différences :

| Monde | Préfixe | Dossier skills | Doc |
|---|---|---|---|
| Carnaval hanté (« Le parc maudit ») | `cv_` | `scripts/enemies/skills/carnival/` | `docs/bestiaire/carnival.md` |
| Les Terres gelées (« Le désert de glace ») | `ice_` | `scripts/enemies/skills/frozen/` | `docs/bestiaire/frozen.md` |
| Les Pyramides d'Égypte (« Le royaume des morts ») | `eg_` | `scripts/enemies/skills/egypt/` | `docs/bestiaire/egypt.md` |

- **Ces mondes n'ont pas encore de carte.** Ne crée PAS de WorldData, de carte, de générateur ni
  d'entrée dans BiomeRegistry. Le bestiaire est décrit dans `data/bestiary/<monde>.tres`
  (ressource `BestiaryData` : `world_id`, `roster` {type de salle : {kind : poids}},
  `elite_kinds` (2), `boss_kind`), prête à être recopiée dans le WorldData quand la carte existera.
  Le chef de projet crée la classe `scripts/enemies/bestiary_data.gd` avant ton lancement.
- Propriété des fichiers : chaque agent ne touche qu'à son préfixe (`data/enemies/<préfixe>*.tres`,
  `assets/sprites/enemies/<préfixe>*/`, `art/blender/bestiary/<monde>/`, son dossier de skills,
  `data/bestiary/<monde>.tres`, `data/loot_tables/enemy_<préfixe>*.tres`, sa section
  `[bestiary_<monde>]` de balance.cfg, `tests/test_bestiary_<monde>.gd`, sa doc, ses captures dans
  `docs/bestiaire/captures/<monde>/`). Fichiers partagés : changements minimaux et additifs, notés
  dans la doc.
- Rendus Blender : `flock /home/claude/.blender_render.lock …` (un seul rendu à la fois, 2 cœurs).
  Godot : `flock /home/claude/.godot.lock godot …`.
- Captures en jeu : pas de carte dédiée → arène de test sur une carte existante (ex. Dust Creek)
  ou scène de démonstration ; la planche de présentation des modèles est l'essentiel.
- Pas de commit des agents : le chef de projet committe et ouvre la PR.
