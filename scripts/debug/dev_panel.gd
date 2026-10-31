class_name DevPanel
extends CanvasLayer
## Mode développeur à l'écran (DevMode), au-dessus de tous les écrans (menus et raid) :
## - badge « DEV » discret (direction D : encre, biseau, accent violet) tant que les ressources
##   sont illimitées, pour ne jamais confondre avec une vraie partie ;
## - section du panneau de debug F3 : bascule « Gemmes et or illimités » (clic, ou F4 quand le F3
##   est ouvert) ; bascule « Tout débloquer » (profil de développement virtuel, DevMode) ;
## - « Donner » : n'importe quelle arme ou objet du catalogue (DevTools.give_*) : en raid, l'arme
##   arrive en main et l'objet dans le sac ; au menu, dans la réserve.
## Créé par GameState uniquement si DevMode.is_available() (jamais en version publiée).

const LAYER := 110

var badge: PanelContainer = null
var panel: PanelContainer = null
var toggle: Button = null
## Bascule « Tout débloquer » (DevMode.set_all_unlocked).
var unlock_toggle: Button = null
## Sélecteur « Donner » : catalogue (DevTools.catalog), quantité, bouton, message.
var give_picker: OptionButton = null
var give_count: SpinBox = null
var give_button: Button = null
var give_label: Label = null
var _catalog: Array[Dictionary] = []
var _root: Control = null


## Crée le calque sous `parent` si le build le permet ; null sinon.
static func attach(parent: Node) -> DevPanel:
	if not DevMode.is_available():
		return null
	var p := DevPanel.new()
	p.name = "DevPanel"
	parent.add_child(p)
	return p


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	DevMode.notifier.changed.connect(func(_on: bool) -> void: refresh())
	DevMode.notifier.unlock_changed.connect(func(_on: bool) -> void: refresh())
	EventBus.debug_toggled.connect(func(_on: bool) -> void: refresh())
	refresh()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Badge : tout petit « DEV » dans le coin bas-gauche (hors contenu), encre + accent violet.
	badge = PanelContainer.new()
	badge.name = "DevBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.78), 7.0, Color(MenuKit.VIOLET, 0.9), 1.0, 10.0, 3.0)
	bs.accent_width = 3.0
	bs.accent_color = MenuKit.VIOLET
	bs.content_margin_left = 10.0
	badge.add_theme_stylebox_override("panel", bs)
	var dev := MenuKit.label("DEV", 15, MenuKit.GOLD, MenuKit.display())
	dev.uppercase = true
	badge.add_child(dev)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 4)
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(badge)

	# Section F3 : coin haut-droit, sous les compteurs de monnaie.
	panel = PanelContainer.new()
	panel.name = "DevSection"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := CutBox.make(Color(MenuKit.NIGHT, 0.88), 10.0, MenuKit.BORDER, 1.0, 14.0, 10.0)
	panel.add_theme_stylebox_override("panel", ps)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(MenuKit.title("Mode développeur", 20, MenuKit.TEXT))
	toggle = MenuKit.chip("Gemmes et or illimités", MenuKit.VIOLET)
	toggle.name = "UnlimitedToggle"
	toggle.custom_minimum_size = Vector2(300, 44)
	toggle.toggled.connect(_on_toggled)
	col.add_child(toggle)
	col.add_child(MenuKit.label("F4 · achats gratuits, solde réel intact", 13, MenuKit.TEXT_DIM, MenuKit.nunito(400)))
	unlock_toggle = MenuKit.chip("Tout débloquer", MenuKit.VIOLET)
	unlock_toggle.name = "UnlockToggle"
	unlock_toggle.custom_minimum_size = Vector2(300, 44)
	unlock_toggle.toggled.connect(func(on: bool) -> void:
		DevMode.set_all_unlocked(on)
		refresh())
	col.add_child(unlock_toggle)
	col.add_child(MenuKit.label("Profil de test, ta sauvegarde est gardée", 13, MenuKit.TEXT_DIM, MenuKit.nunito(400)))
	_build_give(col)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = 88.0
	panel.offset_right = -16.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)


## « Donner » : liste déroulante du catalogue (armes puis objets), quantité, bouton.
func _build_give(col: VBoxContainer) -> void:
	col.add_child(MenuKit.label("Donner", 15, MenuKit.TEXT, MenuKit.nunito(700)))
	give_picker = OptionButton.new()
	give_picker.name = "GivePicker"
	give_picker.custom_minimum_size = Vector2(300, 40)
	give_picker.fit_to_longest_item = false
	_catalog = DevTools.catalog()
	for i: int in _catalog.size():
		var e: Dictionary = _catalog[i]
		var prefix := "Arme" if e["kind"] == &"weapon" else "Objet"
		give_picker.add_item("%s · %s (%s)" % [prefix, e["name"], LootDB.rarity_name(int(e["rarity"]))], i)
		give_picker.set_item_metadata(i, i)
	col.add_child(give_picker)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	give_count = SpinBox.new()
	give_count.name = "GiveCount"
	give_count.min_value = 1
	give_count.max_value = int(Balance.get_value("dev", "give_max_count", 99))
	give_count.value = 1
	give_count.custom_minimum_size = Vector2(110, 40)
	row.add_child(give_count)
	give_button = MenuKit.chip("Donner", MenuKit.VIOLET)
	give_button.name = "GiveButton"
	give_button.toggle_mode = false
	give_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_button.pressed.connect(give_selected)
	row.add_child(give_button)
	give_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(400))
	give_label.name = "GiveLabel"
	col.add_child(give_label)


## Donne l'entrée choisie du sélecteur (quantité = nombre d'exemplaires). Renvoie le message.
func give_selected() -> String:
	var i := give_picker.selected
	if i < 0 or i >= _catalog.size():
		return ""
	var e: Dictionary = _catalog[i]
	var n := int(give_count.value)
	var msg := ""
	if e["kind"] == &"weapon":
		for _k in n:
			msg = DevTools.give_weapon(e["id"])
	else:
		msg = DevTools.give_item(e["id"], n)
	give_label.text = msg if not msg.is_empty() else "Impossible"
	return msg


## Sélectionne une entrée du catalogue par id (tests, raccourcis).
func select_entry(id: StringName) -> bool:
	for i: int in _catalog.size():
		if _catalog[i]["id"] == id:
			give_picker.select(i)
			return true
	return false


func refresh() -> void:
	if badge == null:
		return
	var on := DevMode.is_unlimited()
	var all := DevMode.is_all_unlocked()
	badge.visible = on or all
	unlock_toggle.set_pressed_no_signal(all)
	unlock_toggle.text = "Tout débloquer : %s" % ("oui" if all else "non")
	panel.visible = bool(GameState.debug_enabled)
	toggle.set_pressed_no_signal(on)
	toggle.text = "Gemmes et or illimités : %s" % ("oui" if on else "non")


func _on_toggled(on: bool) -> void:
	DevMode.set_unlimited(on)
	refresh()


## F4 (action toggle_dev_currency) quand le debug F3 est ouvert.
func _unhandled_input(event: InputEvent) -> void:
	if GameState.debug_enabled and event.is_action_pressed("toggle_dev_currency"):
		get_viewport().set_input_as_handled()
		DevMode.toggle()
