extends SceneTree
## Repérage de l'extraction permanente : vrai raid à seed fixe, plan schématique de chaque étage
## (salles, départ, escaliers, extractions actuelles, candidats) + captures en jeu des candidats.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 \
##     -s res://tools/extraction_spots/spots_capture.gd -- --out=DOSSIER --map=res://data/maps/perm_dust_creek.tres \
##     [--spots="A:0:12:30;B:-1:5:8"]
## Sans --spots : plans + dump texte (salles, extractions, distances) seulement.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/extraction_spots/spots_capture_driver.gd") as Script).new()
	driver.name = "SpotsCaptureDriver"
	root.add_child(driver)
