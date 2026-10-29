extends "res://scripts/enemies/skills/charge_skill.gd"
## Shérif Sable-Fou : charge à cheval. Même mécanique que la charge commune (couloir rouge au
## sol pendant le télégraphe, course, renversement, sonné contre un mur), mais le visuel passe
## sur l'animation « charge » (le shérif monté sur son cheval au galop) le temps de la course.

var _mounted: bool = false


func start() -> void:
	_mounted = false
	super.start()


func step(dt: float) -> bool:
	if not _mounted and t >= windup():
		_mounted = true
		e._visual_call(&"set_run_anim", ["charge"])
	return super.step(dt)


func cleanup() -> void:
	super.cleanup()
	if _mounted:
		_mounted = false
		e._visual_call(&"set_run_anim", [""])
