extends Node
## Bus d'événements global. Les systèmes communiquent par ces signaux
## plutôt que de se référencer directement.

@warning_ignore("unused_signal")
signal player_spawned(player: Node2D)
@warning_ignore("unused_signal")
signal player_damaged(amount: float, current_hp: float, max_hp: float)
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal enemy_spawned(enemy: Node2D)
@warning_ignore("unused_signal")
signal enemy_died(enemy: Node2D, position: Vector2)
@warning_ignore("unused_signal")
signal projectile_fired(projectile: Node2D)
@warning_ignore("unused_signal")
signal debug_toggled(enabled: bool)
@warning_ignore("unused_signal")
signal raid_started(seed: int)
@warning_ignore("unused_signal")
signal floor_changed(floor_index: int)
