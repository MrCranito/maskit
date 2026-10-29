extends EnemySkill
## Passif (tireur embusqué) : ses balles traversent les caisses, tonneaux et chariots
## (conteneurs), pas les murs.


func defaults() -> Dictionary:
	return {"passive": true}


func on_fire(projectile: Node) -> void:
	if projectile != null:
		projectile.set(&"pierce_props", true)
