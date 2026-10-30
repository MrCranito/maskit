extends SceneTree
## Point d'entrée de la simulation des drops (drop_sim.gd, chargé après les autoloads).
##   godot --headless --path . -s res://tools/playtest/drop_sim_main.gd -- --out=FICHIER.json [--n=100000]


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var sim: Node = (load("res://tools/playtest/drop_sim.gd") as Script).new()
	sim.name = "DropSim"
	root.add_child(sim)
