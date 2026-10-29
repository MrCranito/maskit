extends Node
## État global de la partie en cours (raid actif, joueur, debug, seed).

var player: Node2D = null
var debug_enabled: bool = false
var run_seed: int = 0
## Inventaire de raid (perdu à la mort, transféré à l'extraction — phase 6).
var raid_inventory: Inventory = Inventory.from_balance()

# --- Difficulté et arsenal (choisis au menu) ---
const DIFFICULTY_NAMES: Array[String] = ["Facile", "Normal", "Difficile", "Infernal", "Cauchemar"]
## Armes emportées dans le raid en cours (ordre des emplacements), fixées par
## Profile.start_raid() au lancement. Vide = raid lancé directement (debug) : pistolet de départ.
var raid_weapons: Array[WeaponData] = []
## Équipement emporté (grenade, mine, C4, drone) ; null = aucun.
var raid_gadget: WeaponData = null
## Difficulté du raid : 0 = Facile … 4 = Cauchemar.
var difficulty: int = 1
## Monde du prochain raid (fixé par la carte choisie ; vide = Far West).
var world_path: String = ""
## Carte du prochain raid (MapCard, scripts/maps/map_card.gd) ; null = raid lancé
## directement (debug) : aucun modificateur.
var current_map: Resource = null
## Debug : heure UTC forcée (secondes Unix) pour la rotation des cartes ; 0 = heure réelle.
var debug_time_override: int = 0


func _ready() -> void:
	randomize()
	run_seed = randi()
	difficulty = int(Balance.get_value("raid", "default_difficulty", 1))
	EventBus.player_spawned.connect(func(p: Node2D) -> void: player = p)
	# SaveManager est un autoload enregistré après GameState : lecture différée.
	_load_settings.call_deferred()


## Lance le raid côté profil : l'arsenal de départ quitte la réserve (perdu en cas de mort).
func begin_raid() -> void:
	raid_inventory = Inventory.from_balance()
	raid_weapons = Profile.start_raid()
	raid_gadget = Profile.raid_gadget


## Choisit la difficulté (bornée à 0..4) et la sauvegarde.
func set_difficulty(value: int, persist: bool = true) -> void:
	difficulty = clampi(value, 0, DIFFICULTY_NAMES.size() - 1)
	if persist:
		_save_settings()


## Fixe la carte du prochain raid : monde, difficulté (propre à la carte, non sauvegardée),
## seed (fixed_seed de la carte, sinon nouvelle seed). null = aucune carte.
func set_current_map(card: Resource, new_seed: bool = true) -> void:
	current_map = card
	if card == null:
		return
	world_path = String(card.get("world_path"))
	difficulty = clampi(int(card.get("difficulty")), 0, DIFFICULTY_NAMES.size() - 1)
	if new_seed:
		var fixed: int = int(card.call("get_fixed_seed")) if card.has_method("get_fixed_seed") else 0
		run_seed = fixed if fixed != 0 else randi()


## Modificateur de la carte en cours (`default` sans carte ou clé absente).
func map_modifier(key: String, default: Variant) -> Variant:
	if current_map == null:
		return default
	var mods: Variant = current_map.get("modifiers")
	return (mods as Dictionary).get(key, default) if mods is Dictionary else default


## Économie d'énergie (ancien interrupteur) : mode « éco » ou mode par défaut (FrameRate).
func apply_power_saving(on: bool) -> void:
	FrameRate.apply(FrameRate.MODE_ECO if on else FrameRate.MODE_MAX)


static func difficulty_name(value: int) -> String:
	return DIFFICULTY_NAMES[clampi(value, 0, DIFFICULTY_NAMES.size() - 1)]


func _load_settings() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	if (sm.get("data") as Dictionary).is_empty() and sm.has_method("load_save"):
		sm.call("load_save")
	var data: Dictionary = sm.get("data")
	difficulty = clampi(int(data.get("difficulty", difficulty)), 0, DIFFICULTY_NAMES.size() - 1)
	# Images par seconde : 120 si l'écran le permet (réglage « Images par seconde »).
	FrameRate.apply(FrameRate.saved_mode())


func _save_settings() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	var data: Dictionary = sm.get("data")
	data["difficulty"] = difficulty
	sm.call("save")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_enabled = not debug_enabled
		EventBus.debug_toggled.emit(debug_enabled)
