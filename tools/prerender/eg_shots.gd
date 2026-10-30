extends SceneTree
## Lanceur : les autoloads ne sont pas nommables depuis un script principal, le scénario est dans
## eg_shots_driver.gd (chargé après les autoloads).
## Captures en jeu de la carte des Pyramides d'Égypte (fenêtre réelle sous xvfb) :
##   xvfb-run -a -s "-screen 0 1300x760x24" godot --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --windowed --path . -s res://tools/prerender/eg_shots.gd -- <dossier> [seed]
## Produit M_overview.png (fond complet via la mini-carte) et M_ingame_1..3.png : avenue des sphinx,
## temple d'angle (toit effacé, joueur dedans), sanctuaire.



func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/prerender/eg_shots_driver.gd") as Script).new()
	driver.name = "EgShotsDriver"
	root.add_child(driver)
