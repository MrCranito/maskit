class_name HeroPoseRect
extends TextureRect
## Pose fixe du héros pour les cartes (boutique, offres, pass) : la pose du lobby recadrée sur sa
## zone utile (ShopScreen.cropped_preview) AVEC l'arme tenue par-dessus — arme principale du
## profil et son skin (Profile.get_main_weapon), ou celle donnée à make() — puis les mains devant.
## Même placement que LobbyHero (LobbyHero.place_held) ; les réglages d'affichage du TextureRect
## (expand_mode, stretch_mode KEEP_ASPECT_CENTERED, ancres) restent ceux de l'appelant.
## `bust` : moitié haute seulement (vignette compacte du pass), l'arme est coupée au bord.

var skin: SkinData = null
## Arme imposée (null : arme principale du profil, suivie quand le profil change).
var weapon: WeaponData = null
var bust: bool = false
var held: Node2D = null
var pivot: Node2D = null
var weapon_view: WeaponView = null
var hands: Sprite2D = null
var _region: Rect2 = Rect2()
var _key: String = "?"


## Carte prête : skin `s`, arme `w` (null : arme principale du profil).
static func make(s: SkinData, w: WeaponData = null, p_bust: bool = false) -> HeroPoseRect:
	var r := HeroPoseRect.new()
	r.skin = s
	r.weapon = w
	r.bust = p_bust
	r._apply_texture()
	return r


func _ready() -> void:
	held = Node2D.new()
	held.name = "Held"
	add_child(held)
	pivot = Node2D.new()
	pivot.name = "WeaponPivot"
	held.add_child(pivot)
	weapon_view = WeaponView.new()
	weapon_view.icon_mode = true
	pivot.add_child(weapon_view)
	hands = Sprite2D.new()
	hands.name = "Hands"
	hands.centered = false
	hands.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	held.add_child(hands)
	if bust:
		clip_contents = true
	resized.connect(_layout)
	Profile.changed.connect(refresh)
	refresh()


func _apply_texture() -> void:
	var tex := ShopScreen.cropped_preview(ShopScreen.pose_texture(skin))
	if bust and tex is AtlasTexture:
		var a := (tex as AtlasTexture).duplicate() as AtlasTexture
		a.region = Rect2(a.region.position, Vector2(a.region.size.x, a.region.size.y * 0.58))
		tex = a
	texture = tex
	_region = (tex as AtlasTexture).region if tex is AtlasTexture else Rect2(Vector2.ZERO, tex.get_size() if tex != null else Vector2.ONE)


## La pose affichée est-elle une pose du lobby rendue sans arme (point de prise connu) ?
func is_lobby_pose() -> bool:
	var base: Texture2D = (texture as AtlasTexture).atlas if texture is AtlasTexture else texture
	return base != null and base.resource_path.begins_with(LobbyHero.DIR) and LobbyHero.poses_have_grip()


## Arme tenue (après refresh).
func get_weapon() -> WeaponData:
	return weapon_view.weapon if weapon_view != null else weapon


func refresh() -> void:
	if weapon_view == null:
		return
	var w: WeaponData = weapon if weapon != null else Profile.get_main_weapon()
	var show := w != null and is_lobby_pose()
	held.visible = show
	if not show:
		return
	var sk := WeaponSkin.equipped_for(w)
	var key := "%s|%s" % [w.id, sk.id if sk != null else ""]
	if key != _key:
		_key = key
		LobbyHero.place_held(pivot, weapon_view, w, false, {})
		hands.texture = LobbyHero.hands_texture(LobbyHero.sheet_for(skin))
		hands.material = HeroSkin.material_for(skin) if not LobbyHero.has_sheet(skin) else null
		if not bust:
			_fit_weapon()
	_layout()


## Agrandit le recadrage pour que l'arme tenue tienne dans la carte (le héros rapetisse un peu).
func _fit_weapon() -> void:
	_apply_texture()
	if not (texture is AtlasTexture):
		return
	var a := texture as AtlasTexture
	var wr := weapon_view.get_item_rect()
	var xf := pivot.transform
	var r := a.region
	for c: Vector2 in [wr.position, wr.position + Vector2(wr.size.x, 0), wr.end, wr.position + Vector2(0, wr.size.y)]:
		r = r.expand(xf * c)
	r = r.grow(6.0).intersection(Rect2(Vector2.ZERO, a.atlas.get_size()))
	if r != a.region:
		var b := a.duplicate() as AtlasTexture
		b.region = r
		texture = b
		_region = r


## Repère du cadre de la pose → contrôle (même calcul que STRETCH_KEEP_ASPECT_CENTERED).
func _layout() -> void:
	if held == null or _region.size.x <= 0.0 or _region.size.y <= 0.0:
		return
	var k: float = minf(size.x / _region.size.x, size.y / _region.size.y)
	var off: Vector2 = (size - _region.size * k) * 0.5
	held.position = off - _region.position * k
	held.scale = Vector2(k, k)
