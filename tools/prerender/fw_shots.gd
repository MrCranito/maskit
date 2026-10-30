extends SceneTree
## Lanceur : les autoloads ne sont pas nommables depuis un script principal, le scénario est dans
## fw_shots_driver.gd (chargé après les autoloads).
## Captures en jeu de Dust Creek (Far West, carte pré-rendue), fenêtre réelle :
##   macOS : godot --audio-driver Dummy --resolution 1280x720 --windowed --path . \
##       -s res://tools/prerender/fw_shots.gd -- <dossier>
##   Linux : xvfb-run -a -s "-screen 0 1300x760x24" godot --rendering-driver opengl3 … (mêmes arguments)
## Produit M_ingame_1..3.png : grand-rue (arrivée), intérieur d'un grand bâtiment (toit effacé,
## joueur dedans), voie ferrée et train.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/prerender/fw_shots_driver.gd") as Script).new()
	driver.name = "FwShotsDriver"
	root.add_child(driver)
