class_name DevPanel
extends CanvasLayer
## Mode développeur à l'écran (DevMode), au-dessus de tous les écrans (menus et raid) :
## - badge « DEV » discret (direction D : encre, biseau, accent violet) tant que les ressources
##   sont illimitées, pour ne jamais confondre avec une vraie partie ;
## - section du panneau de debug F3 : bascule « Gemmes et or illimités » (clic, ou F4 quand le F3
##   est ouvert).
## Créé par GameState uniquement si DevMode.is_available() (jamais en version publiée).

const LAYER := 110

var badge: PanelContainer = null
var panel: PanelContainer = null
var toggle: Button = null
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
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = 88.0
	panel.offset_right = -16.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)


func refresh() -> void:
	if badge == null:
		return
	var on := DevMode.is_unlimited()
	badge.visible = on
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
