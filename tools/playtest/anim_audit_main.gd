extends SceneTree
## Point d'entrée de l'audit des animations (anim_audit.gd, chargé après les autoloads).
##   godot --headless --path . -s res://tools/playtest/anim_audit_main.gd -- --out=DOSSIER


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var sim: Node = (load("res://tools/playtest/anim_audit.gd") as Script).new()
	sim.name = "AnimAudit"
	root.add_child(sim)
