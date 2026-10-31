extends GutTest
## Rendus des armes à feu (art/blender/build_weapons.py) : chaque arme à feu du catalogue a son
## sprite tenu (assets/sprites/weapons/<sprite_id>.png), ses métadonnées .json (grip, muzzle,
## scale, size) cohérentes avec l'image, et son icône d'inventaire (assets/ui/weapons/<sprite_id>.png).
## Aucune ne doit retomber sur la silhouette dessinée en code de sa catégorie.

const SPRITE_DIR := "res://assets/sprites/weapons/"
const ICON_DIR := "res://assets/ui/weapons/"
const FIREARM_COUNT := 30
const ICON_SIZE := Vector2i(256, 128)


func _firearms() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w: WeaponData in WeaponCatalog.all():
		if w.family == "firearm":
			out.append(w)
	return out


func _vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(-1, -1)


func test_catalogue_compte_30_armes_a_feu() -> void:
	assert_eq(_firearms().size(), FIREARM_COUNT, "30 armes à feu au catalogue")


func test_chaque_arme_a_feu_a_un_sprite_tenu_et_un_json_valide() -> void:
	for w: WeaponData in _firearms():
		var sid := String(w.get_sprite_id())
		var png := SPRITE_DIR + sid + ".png"
		assert_true(ResourceLoader.exists(png), "%s : sprite tenu %s" % [w.id, png])
		if not ResourceLoader.exists(png):
			continue
		var tex := load(png) as Texture2D
		assert_not_null(tex, "%s : texture chargeable" % w.id)
		var json_path := SPRITE_DIR + sid + ".json"
		assert_true(FileAccess.file_exists(json_path), "%s : %s" % [w.id, json_path])
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		assert_true(meta is Dictionary, "%s : JSON valide" % w.id)
		if not (meta is Dictionary) or tex == null:
			continue
		var d := meta as Dictionary
		var tsize := Vector2(tex.get_size())
		assert_eq(_vec(d.get("size")), tsize, "%s : size = taille de l'image" % w.id)
		var grip := _vec(d.get("grip"))
		var muzzle := _vec(d.get("muzzle"))
		var bounds := Rect2(Vector2.ZERO, tsize + Vector2.ONE)
		assert_true(bounds.has_point(grip), "%s : grip %s dans l'image" % [w.id, grip])
		assert_true(bounds.has_point(muzzle), "%s : muzzle %s dans l'image" % [w.id, muzzle])
		# Canon vers la droite : la bouche est devant la prise en main, dans le quart droit de l'image.
		assert_gt(muzzle.x, grip.x, "%s : bouche devant la poignée" % w.id)
		assert_gt(muzzle.x, tsize.x * 0.75, "%s : bouche à l'avant de l'image" % w.id)
		# 0.45, ou 0.225 pour les armes HD (deux fois plus de pixels, même taille en jeu).
		var sc := float(d.get("scale", 0.0))
		assert_true(is_equal_approx(sc, 0.45) or is_equal_approx(sc, 0.225), "%s : échelle des armes tenues (%s)" % [w.id, sc])
		assert_eq(int(d.get("rarity", -1)), w.rarity, "%s : rareté du rendu = rareté de l'arme" % w.id)


func test_chaque_arme_a_feu_a_son_icone() -> void:
	for w: WeaponData in _firearms():
		var p := ICON_DIR + String(w.get_sprite_id()) + ".png"
		assert_true(ResourceLoader.exists(p), "%s : icône %s" % [w.id, p])
		if not ResourceLoader.exists(p):
			continue
		var tex := load(p) as Texture2D
		var isz := tex.get_size() if tex != null else Vector2.ZERO
		assert_true(isz == Vector2(ICON_SIZE) or isz == Vector2(ICON_SIZE) * 2.0, "%s : icône 256x128 ou 512x256 (%s)" % [w.id, isz])
		# L'icône résolue par le catalogue est bien celle de l'arme (pas celle de la catégorie).
		assert_eq(WeaponCatalog.icon_for(w), tex, "%s : WeaponCatalog.icon_for" % w.id)


func test_categories_ont_un_repli_rendu() -> void:
	for cat: StringName in WeaponData.CATEGORIES:
		if cat == WeaponData.CAT_GADGET:
			continue
		assert_true(ResourceLoader.exists(SPRITE_DIR + String(cat) + ".png"), "repli tenu %s" % cat)
		assert_true(ResourceLoader.exists(ICON_DIR + String(cat) + ".png"), "repli icône %s" % cat)
