extends SceneTree
## Lanceur : les autoloads ne sont pas nommables depuis un script principal, le scénario est dans
## mall_shots_driver.gd (chargé après les autoloads).
## Captures en jeu des Galeries Lumière (fenêtre réelle ; sous Linux : xvfb-run -a) :
##   godot --audio-driver Dummy --resolution 1280x720 --windowed --path . \
##       -s res://tools/prerender/mall_shots.gd -- <dossier> [seed]
## Produit M_ingame_1..3.png : parking d'arrivée (voiture rouge, entrée), atrium à fontaine,
## boutique à plafond (toit effacé, joueur dedans).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/prerender/mall_shots_driver.gd") as Script).new()
	driver.name = "MallShotsDriver"
	root.add_child(driver)
