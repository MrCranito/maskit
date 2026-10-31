extends SceneTree
## Captures de la mini-carte, du bouton sac et de la carte plein écran (PR « mini-carte lisse ») :
## vrai raid à seed fixe, quelques déplacements pour explorer, puis HUD, recadrage du coin haut
## droit agrandi ×2 (plus proche voisin : on voit les vrais pixels), carte entière, zoom max.
##   godot --path . --resolution 2000x923 -s res://tools/minimap_capture/minimap_capture.gd -- \
##       --out=C:/dossier --tag=apres_dust --map=res://data/maps/perm_dust_creek.tres [--floor=-1]
## Isoler la sauvegarde : override.cfg (non commité) avec
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_<moi>"


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/minimap_capture/minimap_capture_driver.gd") as Script).new()
	driver.name = "MinimapCaptureDriver"
	root.add_child(driver)
