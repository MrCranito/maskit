extends SceneTree
## Captures de comparaison des réglages d'import (PR « chore/taille-apk ») : même scène, même
## seed, même résolution, avant / après un changement de compression des textures.
##   godot --path . --resolution 1600x900 -s res://tools/apk_capture/apk_capture.gd -- \
##       --out=C:/dossier/captures --prefix=avant|apres [--only=dust,mall,enemy,menu]
## Images : <prefix>_<scène>.png + <prefix>_<scène>_zoom.png (recadrage ×2 autour du point
## d'intérêt, sans lissage : chaque pixel d'origine devient 2×2).
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.
## Le scénario est dans apk_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/apk_capture/apk_capture_driver.gd") as Script).new()
	driver.name = "ApkCaptureDriver"
	root.add_child(driver)
