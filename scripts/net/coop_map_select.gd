class_name CoopMapSelect
extends MapSelect
## Choix de la carte par l'hôte d'un salon coop : même écran que « Jouer » (MapSelect), affiché
## par-dessus le salon ; le bouton d'action choisit la carte et revient au salon au lieu
## d'ouvrir l'arsenal.

signal chosen(card: MapCard)
signal closed


func _ready() -> void:
	next_scene = ""
	super._ready()


func _refresh_launch() -> void:
	super._refresh_launch()
	launch_button.text = "Choisir cette carte"
	if not launch_button.disabled:
		_d_status.text = "Pour ton salon coop"


func launch_selected() -> bool:
	var card: MapCard = selected_entry.get("card") as MapCard
	_refresh_launch()
	if card == null or launch_button.disabled:
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"confirm")
	chosen.emit(card)
	queue_free()
	return true


func go_back() -> void:
	MenuKit.sfx(&"back")
	closed.emit()
	queue_free()
