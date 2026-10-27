# Conventions techniques (contrat entre modules)

## Moteur
- Godot 4.4.1, GDScript **typé** (annoter variables, paramètres, retours).
- Binaire : `godot` (dans le PATH). Projet : `/home/claude/royaumes-des-masques`.
- Vérif compilation : `godot --headless --path . --import` puis `godot --headless --path . --quit`.
- Vérif exécution de la scène principale : `godot --headless --path . --quit-after 300` (aucune erreur SCRIPT ERROR ne doit sortir).
- Résolution de référence : 720 x 1280 (portrait, style Archero).

## Autoloads (déjà écrits, ne pas modifier sans raison)
- `EventBus` : signaux globaux (player_spawned, player_damaged, player_died, enemy_spawned, enemy_died, projectile_fired, debug_toggled).
- `Balance` : `Balance.get_float("section", "cle", defaut)` / `Balance.get_value(...)`. Fichier : `data/balance.cfg`. Toute valeur d'équilibrage y va.
- `InputSetup` : actions `move_up/down/left/right` (ZQSD + WASD + flèches), `toggle_debug` (F3), `interact` (E), `fire_manual` (clic gauche).
- `GameState` : `player`, `debug_enabled`, `run_seed`. Bascule le debug sur F3 et émet `EventBus.debug_toggled`.
- `SaveManager`, `LootManager` : stubs.

## Couches de collision (numéro de couche → valeur bitmask)
| Couche | Nom | Bit |
|---|---|---|
| 1 | world (murs) | 1 |
| 2 | player | 2 |
| 3 | enemies | 4 |
| 4 | player_projectiles | 8 |
| 5 | enemy_projectiles | 16 |
| 6 | interactables | 32 |

## Groupes
- `player` : le joueur.
- `enemies` : toute cible ennemie (le tir auto cible ce groupe).
- `damageable` : tout ce qui encaisse des dégâts.
- `enemy_units` : tous les ennemis, morts ou vivants (pour les compteurs). `enemies` ne contient que les ennemis ciblables.

## Interface de dégâts
Tout nœud du groupe `damageable` implémente :
```gdscript
func take_damage(amount: float, source: Node) -> void
func is_alive() -> bool
```

## Chemins partagés (phase 1)
- Joueur : `res://scenes/player/player.tscn` (racine CharacterBody2D, script `res://scripts/player/player.gd`, classe `Player`).
  - Propriétés publiques : `hp: float`, `max_hp: float`, `weapon: WeaponData`, `current_target: Node2D` (peut être null).
  - Contient sa propre Camera2D.
  - Émet `EventBus.player_spawned.emit(self)` dans `_ready`.
- Joystick virtuel : `res://scenes/ui/virtual_joystick.tscn` (Control, script `res://scripts/ui/virtual_joystick.gd`, classe `VirtualJoystick`), propriété `output: Vector2` (longueur 0..1). Le joueur le trouve via le groupe `virtual_joystick`.
- Ressource arme : `res://scripts/combat/weapon_data.gd` (classe `WeaponData`, Resource).
- Projectile : `res://scenes/combat/projectile.tscn`, pooling via `res://scripts/combat/projectile_pool.gd` (classe `ProjectilePool`).
- Cible d'entraînement : `res://scenes/enemies/target_dummy.tscn`.
- Overlay debug : `res://scenes/ui/debug_overlay.tscn`.
- Scène principale : `res://scenes/rooms/test_room.tscn`.

## Style
- Placeholders dessinés en code (`_draw()`), couleurs chaudes, contours nets.
- Construire les structures complexes en code ; garder les .tscn minimaux.
- Commentaires et textes de jeu en français.
