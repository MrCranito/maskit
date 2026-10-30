class_name HeroPreview
extends Control
## Aperçu du héros pour les menus (boutique, pass) : MÊME rendu que le lobby — pose fixe haute
## résolution par skin (assets/ui/menu/hero/<skin>.png) animée par l'idle procédurale de
## LobbyHero (respiration + balancement), ombre au sol, réaction au changement de skin. Le héros
## tient l'arme principale du profil (avec son skin), ou celle imposée par set_weapon (coéquipier).
## Aucune rotation image par image : net et fluide. Le héros est posé pieds en bas au centre,
## à la hauteur `height_ratio` × hauteur de la boîte.

const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

var hero: LobbyHero = null
var glow: TextureRect = null
var skin: SkinData = null
## Conservé pour compatibilité (l'aperçu ne tourne plus sur lui-même).
var turning: bool = false
## Hauteur du héros rapportée à la boîte (< 0 : balance.cfg [menu] preview_height_ratio).
var height_ratio: float = -1.0
## Position des pieds (fraction de la hauteur de la boîte).
var feet_ratio: float = 0.94
var _use_current: bool = true
var _weapon_set: bool = false
var _weapon: WeaponData = null
var _weapon_skins: Dictionary = {}


func _init(_p_turning: bool = false) -> void:
	turning = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	clip_contents = false
	glow = TextureRect.new()
	glow.texture = GLOW
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.self_modulate = Color(1.0, 0.72, 0.5, 0.55)
	add_child(glow)
	hero = LobbyHero.new(false)
	hero.skin = HeroSkin.current() if _use_current else skin
	if _weapon_set:
		hero.set_weapon(_weapon, _weapon_skins)
	add_child(hero)
	resized.connect(_layout)
	_layout()


## Affiche ce skin (null = apparence par défaut). Sans appel : skin porté (HeroSkin.current()).
func set_skin(s: SkinData, animate: bool = true) -> void:
	var changed := s != skin or _use_current
	skin = s
	_use_current = false
	if hero != null and hero.sprite != null and changed:
		hero.set_skin(s, animate and is_visible_in_tree())


## Impose l'arme tenue et ses skins (coéquipier) ; sans appel : arme principale du profil local.
func set_weapon(w: WeaponData, skin_ids: Dictionary = {}) -> void:
	_weapon_set = true
	_weapon = w
	_weapon_skins = skin_ids
	if hero != null:
		hero.set_weapon(w, skin_ids)


## Arme tenue (null : aucune).
func get_weapon() -> WeaponData:
	return hero.weapon if hero != null else _weapon


## Id de la pose affichée (« default », « cyber »…).
func get_sheet_id() -> String:
	return hero.sheet_id if hero != null else ""


func get_current_animation() -> StringName:
	return hero.get_current_animation() if hero != null else &""


func _layout() -> void:
	if hero == null:
		return
	var hr: float = height_ratio if height_ratio > 0.0 else Balance.get_float("menu", "preview_height_ratio", 0.95)
	var feet := Vector2(size.x * 0.5, size.y * feet_ratio)
	hero.position = feet
	hero.height_px = maxf(size.y * hr, 1.0)
	var gw: float = minf(size.x * 0.95, hero.height_px * 0.9)
	glow.size = Vector2(gw, gw * 0.3)
	glow.position = feet - glow.size * 0.5
