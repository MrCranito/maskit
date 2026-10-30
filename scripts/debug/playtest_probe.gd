class_name PlaytestProbe
extends RefCounted
## Instrumentation des parties automatiques (tools/playtest). DÉSACTIVÉE par défaut : seul le
## bot de playtest l'active (enabled = true) et branche son collecteur (sink). Sans effet en jeu.
## Le collecteur implémente on_player_hit(amount: float, source: Node).

static var enabled: bool = false
static var sink: Object = null


## Dégâts réellement encaissés par le joueur (après invulnérabilité), avec leur source.
static func player_hit(amount: float, source: Node) -> void:
	if sink != null and is_instance_valid(sink):
		sink.call(&"on_player_hit", amount, source)
