extends SceneTree
## Lanceur : les autoloads ne sont pas nommables depuis un script principal, le scénario est dans
## ss_shots_driver.gd (chargé après les autoloads).
## Captures en jeu de la Station Kagami (fenêtre réelle ; sous Linux : xvfb-run -a) :
##   godot --audio-driver Dummy --resolution 1280x720 --windowed --path . \
##       -s res://tools/prerender/ss_shots.gd -- <dossier> [seed]
## Produit M_ingame_1..3.png : coursive sud depuis le hangar, centre de contrôle (dôme effacé,
## joueur dedans), module de l'aile nord.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/prerender/ss_shots_driver.gd") as Script).new()
	driver.name = "SsShotsDriver"
	root.add_child(driver)
