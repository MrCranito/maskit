# Les Royaumes des Masques : Extraction

Rogue-lite d'extraction en vue de dessus, dans l'esprit d'Archero, pour PC et mobile. Développé avec **Godot 4.4** en GDScript typé.

## Le jeu

Vous enfilez un **masque**, et ce masque fait de vous quelqu'un d'autre : le **Colosse** frappe lentement mais fort et encaisse tout, le **Spectre** esquive et surgit dans le dos, l'**Alchimiste** fait exploser le terrain, le **Marionnettiste** combat entouré de ses invocations.

Depuis le hub, vous choisissez un masque, votre équipement et une difficulté (de Facile à Cauchemar), puis vous partez en raid dans l'un des quatre **royaumes** : Pierre et cristal, Bois et tissu, Métal et horlogerie, Créatures vivantes. Chaque donjon est généré à partir d'une seed. Il est plongé dans un **brouillard de guerre** et vous révélez les salles en avançant ; les murs bloquent la vue.

Vous fouillez les coffres, tonneaux, épaves et cadavres. Certains ennemis lâchent, très rarement, une **clef spéciale** qui ouvre une salle de **super-loot** scellée, gardée par des élites et riche en objets épiques et légendaires.

Ce que vous trouvez ne vous appartient qu'après l'**extraction**. Il faut rejoindre un point d'extraction et tenir pendant la canalisation, pendant que les ennemis attaquent. Si vous mourez, vous perdez le butin du raid.

## Contrôles

| Action | PC | Mobile |
|---|---|---|
| Se déplacer | ZQSD / WASD / flèches | Joystick virtuel |
| Tirer | Automatique sur l'ennemi le plus proche, quand vous êtes immobile | Automatique |
| Tir manuel (visée) | Clic gauche | — |
| Interagir | E | — |
| Overlay de debug | F3 | — |

## Installation

1. Installez [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/) (version standard, pas .NET).
2. Clonez le dépôt :
   ```bash
   git clone <url-du-depot> royaumes-des-masques
   ```
3. Dans le gestionnaire de projets de Godot, cliquez sur **Importer** et sélectionnez `project.godot`.
4. Appuyez sur **F5** pour lancer le jeu.

## Lancer les tests

Les tests utilisent [GUT](https://github.com/bitwes/Gut) 9.4.0, installé dans `addons/gut`.

En ligne de commande (headless) :

```bash
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
# Un seul fichier :
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_balance.gd -gexit
```

La configuration par défaut se trouve dans `.gutconfig.json`. Dans l'éditeur, les tests se lancent depuis le panneau **GUT** en bas de l'écran.

Une CI GitHub Actions (`.github/workflows/tests.yml`) exécute les tests à chaque pull request et à chaque push sur `develop` ou `main`.

## Structure du projet

```
addons/gut/      Framework de tests GUT
assets/          Sprites, sons, musiques, shaders (binaires stockés directement dans git)
data/            Données de jeu : armes, ennemis, tables de loot, masques… + balance.cfg
docs/            Conventions techniques (contrat entre modules)
scenes/          Scènes : player, enemies, rooms, ui, hub, combat
scripts/         Code : core (autoloads), combat, ai, loot, dungeon, inventory, save
tests/           Tests unitaires GUT (fichiers test_*.gd)
.github/         Workflows CI (tests, exports)
```

Les valeurs d'équilibrage ne sont jamais écrites dans le code. Elles se trouvent dans `data/balance.cfg` et dans les ressources `.tres` de `data/`.

## État d'avancement

**Phase 1 en cours** : dépôt, structure, joueur (déplacement et tir automatique), caméra, debug F3.
Le détail de toutes les phases est dans [ROADMAP.md](ROADMAP.md).

## Exports

Quand vous poussez un tag `v*` (par exemple `git tag v0.1.0 && git push origin v0.1.0`), le workflow `.github/workflows/export.yml` exporte les versions Windows, Linux, Web et Android et crée une Release GitHub avec les zips.
Pour l'Android, si les secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS` et `ANDROID_KEYSTORE_PASSWORD` ne sont pas définis, le workflow produit un APK **de debug** signé avec un keystore jetable.

## Relier à GitHub

Le dépôt est publié sur GitHub : https://github.com/MrCranito/maskit

```bash
git clone https://github.com/MrCranito/maskit
```

- Le travail est poussé directement sur `main` ; les pull requests ne sont utilisées que sur demande.
- Les tests GUT tournent automatiquement à chaque push (`.github/workflows/tests.yml`).
- Pour produire les exports Windows, Linux, Web et Android, créez un tag : `git tag v0.1.0 && git push origin v0.1.0`.
- Les binaires (png, ogg, wav, ttf…) sont stockés directement dans git (Git LFS n'est pas utilisé).

## Licence

[MIT](LICENSE) © 2026 Victor Moreau

## Export iOS (Xcode)

Godot exporte un projet Xcode (preset « iOS »), à compiler sur un Mac :

```bash
godot --headless --path . --export-debug "iOS" build/ios/Maskit.xcodeproj
python3 tools/ios_fix_xcode.py build/ios/Maskit.xcodeproj
```

Le script corrige deux défauts des modèles iOS de Godot 4.4.1 : « Framework 'MetalFX' not found » (MetalFX lié seulement sur iPhone) et « Undefined symbol: _main » sur le simulateur des Mac Apple Silicon (la bibliothèque du simulateur ne contient que du x86_64 : le simulateur tourne alors sous Rosetta). Sur un vrai iPhone, aucune restriction.
