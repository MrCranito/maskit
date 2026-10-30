extends SceneTree
## Captures des impacts de balles (PR « impacts des balles ») : raid Station Kagami à seed fixe,
## trois ennemis alignés devant le joueur (IA gelée, visuels animés), rafales ralenties.
##   godot --path . --resolution 1280x720 -s res://tools/impact_capture/impact_capture.gd -- \
##       --out=C:/dossier/captures [--prefix=apres] [--weapons=lmg_m60,pistol_glock18]
## Isoler la sauvegarde : override.cfg (non commité) avec un dossier utilisateur dédié.
## Le scénario est dans impact_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/impact_capture/impact_capture_driver.gd") as Script).new()
	driver.name = "ImpactCaptureDriver"
	root.add_child(driver)
