extends SceneTree
## Captures des extractions permanente / temporaires et des trappes d'urgence (PR
## « extractions permanente et urgence ») : vrai raid à seed fixe, IA gelée.
##   godot --path . --resolution 1600x740 -s res://tools/extraction_capture/hatch_capture.gd -- \
##       --out=DOSSIER [--map=res://data/maps/perm_dust_creek.tres] [--seed=N]
## Sorties : permanente.png, trappe_fermee.png, trappe_sans_clef.png, trappe_ouverte.png,
## carte.png (carte plein écran de l'étage), carte_autre_etage.png (autre étage : extractions
## de l'étage de départ en transparence).
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/extraction_capture/hatch_capture_driver.gd") as Script).new()
	driver.name = "HatchCaptureDriver"
	root.add_child(driver)
