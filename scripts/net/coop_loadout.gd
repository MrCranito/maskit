class_name CoopLoadout
extends ArsenalScreen
## Validation de l'arsenal de départ dans un salon coop : même écran que l'arsenal de départ
## (ArsenalScreen, loadout_mode), affiché par-dessus le salon. « Valider » enregistre l'arsenal
## (Profile.set_loadout) et marque le joueur « prêt » sans lancer le raid : le lancement est
## synchronisé par l'hôte (GameState.begin_raid() est appelé à ce moment-là).

signal validated
signal closed


func _ready() -> void:
	loadout_mode = true
	raid_scene = ""
	super._ready()
	if validate_button != null:
		validate_button.text = "Valider mon arsenal"
		fit_validate_text()


func validate_and_go() -> bool:
	if selected_weapon_count() == 0:
		MenuKit.sfx(&"error")
		return false
	Profile.set_loadout(selected_uids)
	if not Profile.can_start_raid():
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"confirm_big")
	validated.emit()
	queue_free()
	return true


func go_back() -> void:
	MenuKit.sfx(&"back")
	Profile.set_loadout(selected_uids)
	closed.emit()
	queue_free()
