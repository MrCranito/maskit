class_name WeaponIcon
extends Control
## Icône d'arme pour les menus : WeaponCatalog.icon_for(w) (assets/ui/weapons/…), skin
## d'arme appliqué (WeaponSkin) ; repli si l'icône manque : silhouette dessinée selon la
## catégorie (teintée par le skin). Dessin statique, redessiné seulement si l'arme,
## le skin ou la taille changent.

var weapon: WeaponData = null
var skin: SkinData = null
## Utilise le skin équipé du profil (sinon `skin` tel quel).
var use_equipped_skin: bool = true
var tex_rect: TextureRect = null

## Silhouettes de repli (coordonnées normalisées dans une boîte 2:1, canon vers la droite) :
## liste de rectangles [x, y, w, h] ; le dernier élément peut être une crosse en polygone.
const SHAPES := {
	&"pistol": [[0.3, 0.3, 0.42, 0.14], [0.32, 0.42, 0.12, 0.34], [0.44, 0.44, 0.06, 0.08]],
	&"revolver": [[0.22, 0.32, 0.5, 0.1], [0.36, 0.28, 0.16, 0.2], [0.26, 0.44, 0.12, 0.34]],
	&"smg": [[0.18, 0.32, 0.56, 0.16], [0.72, 0.36, 0.12, 0.07], [0.3, 0.46, 0.09, 0.3], [0.46, 0.46, 0.08, 0.34], [0.06, 0.36, 0.13, 0.1]],
	&"shotgun": [[0.12, 0.34, 0.8, 0.1], [0.4, 0.44, 0.34, 0.08], [0.02, 0.36, 0.2, 0.2]],
	&"rifle": [[0.16, 0.32, 0.58, 0.15], [0.72, 0.36, 0.22, 0.06], [0.38, 0.46, 0.09, 0.3], [0.5, 0.46, 0.07, 0.22], [0.02, 0.34, 0.16, 0.2]],
	&"sniper": [[0.14, 0.38, 0.5, 0.12], [0.62, 0.41, 0.36, 0.05], [0.3, 0.24, 0.26, 0.1], [0.36, 0.5, 0.07, 0.24], [0.0, 0.38, 0.16, 0.2]],
	&"lmg": [[0.14, 0.3, 0.6, 0.2], [0.72, 0.36, 0.24, 0.07], [0.36, 0.5, 0.2, 0.24], [0.26, 0.5, 0.07, 0.22], [0.0, 0.32, 0.16, 0.2]],
	&"rocket_launcher": [[0.06, 0.32, 0.86, 0.2], [0.88, 0.28, 0.1, 0.28], [0.34, 0.52, 0.08, 0.24], [0.52, 0.52, 0.06, 0.18]],
	&"grenade_launcher": [[0.3, 0.3, 0.44, 0.2], [0.36, 0.26, 0.22, 0.28], [0.36, 0.52, 0.08, 0.24], [0.06, 0.34, 0.24, 0.14]],
}


func _init(w: WeaponData = null) -> void:
	weapon = w


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect = TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex_rect)
	resized.connect(queue_redraw)
	refresh()


func set_weapon(w: WeaponData, p_skin: SkinData = null, p_use_equipped: bool = true) -> void:
	weapon = w
	skin = p_skin
	use_equipped_skin = p_use_equipped
	refresh()


func current_skin() -> SkinData:
	if weapon == null:
		return null
	if skin != null:
		return skin if skin.applies_to(weapon.category) else null
	return Profile.get_weapon_skin(weapon.category) if use_equipped_skin else null


## Icône d'inventaire, sinon sprite tenu (assets/sprites/weapons/<sprite_id>.png), sinon null
## (silhouette dessinée).
static func texture_for(w: WeaponData) -> Texture2D:
	if w == null:
		return null
	var t: Texture2D = WeaponCatalog.icon_for(w)
	if t != null:
		return t
	for cand: StringName in [w.get_sprite_id(), w.category]:
		var p := "res://assets/sprites/weapons/%s.png" % cand
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


func has_texture() -> bool:
	return tex_rect != null and tex_rect.texture != null


func refresh() -> void:
	if tex_rect == null:
		return
	tex_rect.texture = texture_for(weapon)
	WeaponSkin.apply(tex_rect, current_skin())
	queue_redraw()


func _draw() -> void:
	if weapon == null or has_texture():
		return
	var shapes: Array = SHAPES.get(weapon.category, SHAPES[&"pistol"])
	var box := Vector2(size.x, size.x * 0.5)
	if box.y > size.y:
		box = Vector2(size.y * 2.0, size.y)
	var o := (size - box) * 0.5
	var sk := current_skin()
	var body: Color = sk.color_primary if sk != null else Color(0.62, 0.66, 0.74)
	var dark: Color = sk.color_secondary.darkened(0.3) if sk != null else Color(0.3, 0.33, 0.4)
	var outline := Color(0.03, 0.04, 0.09, 0.95)
	var ow: float = maxf(2.0, box.y * 0.04)
	for r: Array in shapes:
		var rect := Rect2(o + Vector2(r[0], r[1]) * box, Vector2(r[2], r[3]) * box)
		draw_rect(rect.grow(ow), outline)
	for i: int in shapes.size():
		var r: Array = shapes[i]
		var rect := Rect2(o + Vector2(r[0], r[1]) * box, Vector2(r[2], r[3]) * box)
		draw_rect(rect, body if i == 0 else body.lerp(dark, 0.45))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, maxf(2.0, rect.size.y * 0.22))), Color(1, 1, 1, 0.22))
