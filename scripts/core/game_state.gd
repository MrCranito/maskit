extends Node
## État global de la partie en cours (raid actif, joueur, debug, seed).

var player: Node2D = null
var debug_enabled: bool = false
var run_seed: int = 0
## Inventaire de raid (perdu à la mort, transféré à l'extraction — phase 6).
var raid_inventory: Inventory = Inventory.from_balance()

# --- Masque et difficulté (choisis au menu, sauvegardés via SaveManager) ---
const DIFFICULTY_NAMES: Array[String] = ["Facile", "Normal", "Difficile", "Infernal", "Cauchemar"]
## Masque porté au prochain raid (id de data/masks/<id>.tres).
var selected_mask_id: StringName = &"kitsune"
## Difficulté du raid : 0 = Facile … 4 = Cauchemar.
var difficulty: int = 1
## Monde du prochain raid (fixé par la carte choisie ; vide = Far West).
var world_path: String = ""


func _ready() -> void:
	randomize()
	run_seed = randi()
	difficulty = int(Balance.get_value("raid", "default_difficulty", 1))
	EventBus.player_spawned.connect(func(p: Node2D) -> void: player = p)
	# SaveManager est un autoload enregistré après GameState : lecture différée.
	_load_mask_choice.call_deferred()


## Ressource du masque sélectionné (repli : kitsune).
func get_selected_mask() -> MaskData:
	return MaskData.load_mask(selected_mask_id)


## Choisit le masque (id inconnu → ignoré, renvoie false) et le sauvegarde.
func set_selected_mask(mask_id: StringName, persist: bool = true) -> bool:
	if not MaskData.exists(mask_id):
		return false
	selected_mask_id = mask_id
	if persist:
		_save_mask_choice()
	return true


## Choisit la difficulté (bornée à 0..4) et la sauvegarde.
func set_difficulty(value: int, persist: bool = true) -> void:
	difficulty = clampi(value, 0, DIFFICULTY_NAMES.size() - 1)
	if persist:
		_save_mask_choice()


## Économie d'énergie : 30 images/s au lieu de 60 (moins de chauffe et de batterie).
func apply_power_saving(on: bool) -> void:
	Engine.max_fps = 30 if on else 60


static func difficulty_name(value: int) -> String:
	return DIFFICULTY_NAMES[clampi(value, 0, DIFFICULTY_NAMES.size() - 1)]


func _load_mask_choice() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	if (sm.get("data") as Dictionary).is_empty() and sm.has_method("load_save"):
		sm.call("load_save")
	var data: Dictionary = sm.get("data")
	var saved_mask := StringName(str(data.get("selected_mask_id", selected_mask_id)))
	if MaskData.exists(saved_mask):
		selected_mask_id = saved_mask
	difficulty = clampi(int(data.get("difficulty", difficulty)), 0, DIFFICULTY_NAMES.size() - 1)
	var settings: Variant = data.get("settings", {})
	if settings is Dictionary:
		apply_power_saving(bool((settings as Dictionary).get("power_saving", false)))


func _save_mask_choice() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	var data: Dictionary = sm.get("data")
	data["selected_mask_id"] = String(selected_mask_id)
	data["difficulty"] = difficulty
	sm.call("save")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_enabled = not debug_enabled
		EventBus.debug_toggled.emit(debug_enabled)
