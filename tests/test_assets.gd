extends GutTest
## Vérifie que les assets (audio, polices, icônes, planches du héros et skins, sprites et icônes
## d'armes) sont présents, au bon format, et se chargent.

const AudioManagerScript := preload("res://scripts/core/audio_manager.gd")

const FONTS: Array[String] = [
	"res://assets/fonts/rye/Rye-Regular.ttf",
	"res://assets/fonts/nunito/Nunito-Variable.ttf",
]

const ICONS_DIR := "res://assets/third_party/icons/"


func test_tous_les_sons_se_chargent() -> void:
	var paths: PackedStringArray = AudioManagerScript.all_paths()
	assert_gt(paths.size(), 50, "la table audio doit contenir des sons")
	for path: String in paths:
		assert_true(ResourceLoader.exists(path), "fichier audio manquant : %s" % path)
		var stream := load(path) as AudioStream
		assert_not_null(stream, "impossible de charger : %s" % path)
		if stream != null:
			assert_gt(stream.get_length(), 0.0, "son vide : %s" % path)


func test_musiques_en_boucle() -> void:
	for key: StringName in AudioManagerScript.MUSIC:
		var stream := load(AudioManagerScript.MUSIC[key]) as AudioStreamOggVorbis
		assert_not_null(stream, "musique non chargée : %s" % key)
		if stream != null:
			assert_true(stream.loop, "la musique doit boucler : %s" % key)


func test_sons_ne_bouclent_pas() -> void:
	for key: StringName in AudioManagerScript.SFX:
		if key == &"desert_wind" or key == &"steps_loop":
			continue
		for path: String in AudioManagerScript.SFX[key]:
			var stream := load(path) as AudioStreamOggVorbis
			if stream != null:
				assert_false(stream.loop, "un effet ne doit pas boucler : %s" % path)


func test_polices_se_chargent() -> void:
	for path: String in FONTS:
		var font := load(path) as FontFile
		assert_not_null(font, "police non chargée : %s" % path)


func test_icones_se_chargent() -> void:
	var files := DirAccess.get_files_at(ICONS_DIR)
	var count := 0
	for f: String in files:
		if f.ends_with(".svg"):
			count += 1
			var tex := load(ICONS_DIR + f) as Texture2D
			assert_not_null(tex, "icône non chargée : %s" % f)
	assert_gt(count, 40, "au moins 40 icônes attendues")


func test_audio_manager_api() -> void:
	var am: Node = AudioManagerScript.new()
	add_child_autofree(am)
	assert_true(am.has_sfx(&"revolver_shot"))
	assert_false(am.has_sfx(&"inexistant"))
	assert_true(am.play_sfx(&"click"))
	assert_true(am.play_sfx(&"golem_stomp", Vector2(10, 10)))
	assert_true(am.play_music(&"western_explore", false))
	am.stop_music(false)


# --- Héros, skins de personnage, armes (agent Art) ---------------------------------

const HERO_DIR := "res://assets/sprites/hero3d/"
const CHAR_SKINS: Array[StringName] = [&"default", &"gign", &"fantome", &"sas", &"desert", &"forest",
	&"spetsnaz", &"cyber", &"scorpion"]
const CHAR_PRICES: Array[int] = [0, 250, 250, 500, 500, 500, 1000, 1000, 1000]
const CHAR_RARITIES: Array[int] = [0, 2, 2, 3, 3, 3, 4, 4, 4]
const HERO_ANIMS: Array[String] = ["idle", "run", "backpedal", "strafe_l", "strafe_r", "hit"]
const HERO_DIRS: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const WEAPON_IDS: Array[String] = [
	"pistol_p9", "pistol_glock18", "pistol_deagle", "pistol_p320",
	"smg_mp5", "smg_vector", "smg_p90", "smg_uzi",
	"rifle_ak47", "rifle_m4a1", "rifle_scarh", "rifle_aug",
	"sniper_m24", "sniper_ax50", "sniper_m82",
	"rocket_rpg7", "rocket_m202", "rocket_javelin",
	"gadget_frag", "gadget_smoke", "gadget_mine", "gadget_c4", "gadget_drone",
]
const GADGET_IDS: Array[String] = ["gadget_frag", "gadget_smoke", "gadget_mine", "gadget_c4", "gadget_drone"]


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _check_hero_dir(dir: String) -> void:
	var meta := _read_json(dir.path_join("hero_meta.json"))
	assert_false(meta.is_empty(), "hero_meta.json manquant ou invalide : %s" % dir)
	if meta.is_empty():
		return
	for k: String in ["frame_size", "feet_offset", "display_height", "fps", "frames", "sheets", "directions", "hand_height"]:
		assert_true(meta.has(k), "%s : clé %s absente de hero_meta.json" % [dir, k])
	var fs: Array = meta.get("frame_size", [0, 0])
	var sf := load(dir.path_join("hero_frames.tres")) as SpriteFrames
	assert_not_null(sf, "hero_frames.tres non chargé : %s" % dir)
	if sf == null:
		return
	var frames: Dictionary = meta.get("frames", {})
	for anim: String in HERO_ANIMS:
		assert_true(frames.has(anim), "%s : anim %s absente du meta" % [dir, anim])
		var n := int(frames.get(anim, 0))
		var sheet := load(String(meta["sheets"].get(anim, ""))) as Texture2D
		assert_not_null(sheet, "%s : planche %s manquante" % [dir, anim])
		if sheet != null:
			assert_eq(sheet.get_width(), int(fs[0]) * n, "%s : largeur de planche %s" % [dir, anim])
			assert_eq(sheet.get_height(), int(fs[1]) * HERO_DIRS.size(), "%s : hauteur de planche %s" % [dir, anim])
		for d: String in HERO_DIRS:
			var name := StringName("%s_%s" % [anim, d])
			assert_true(sf.has_animation(name), "%s : animation %s absente" % [dir, name])
			if sf.has_animation(name):
				assert_eq(sf.get_frame_count(name), n, "%s : nb d'images de %s" % [dir, name])
				assert_eq(sf.get_animation_loop(name), anim != "hit", "%s : boucle de %s" % [dir, name])
				var tex := sf.get_frame_texture(name, 0)
				assert_eq(Vector2i(tex.get_size()), Vector2i(int(fs[0]), int(fs[1])), "%s : taille d'image %s" % [dir, name])


func test_planches_heros_par_defaut() -> void:
	_check_hero_dir(HERO_DIR)
	var meta := _read_json(HERO_DIR + "hero_meta.json")
	assert_almost_eq(float(meta.get("display_height", 0.0)), 82.6, 20.0, "échelle du héros compatible")


func test_planches_skins_personnage() -> void:
	for sid: StringName in CHAR_SKINS:
		var path := "res://data/skins/char_%s.tres" % sid
		assert_true(ResourceLoader.exists(path), "skin manquant : %s" % path)
		var skin := load(path) as SkinData
		assert_not_null(skin, "skin non chargé : %s" % path)
		if skin == null:
			continue
		assert_eq(skin.kind, SkinData.KIND_CHARACTER)
		assert_eq(String(skin.id), "char_%s" % sid)
		assert_not_null(skin.preview, "aperçu manquant : %s" % sid)
		assert_ne(HeroSkin.sprite_dir_for(skin), "", "dossier de planches : %s" % sid)
		_check_hero_dir(skin.sprite_dir)
		assert_not_null(HeroSkin.frames_for(skin))
		assert_false(HeroSkin.meta_for(skin).is_empty())
	for k: int in CHAR_SKINS.size():
		var s := load("res://data/skins/char_%s.tres" % CHAR_SKINS[k]) as SkinData
		if s == null:
			continue
		assert_eq(s.price_gems, CHAR_PRICES[k], "prix de %s" % CHAR_SKINS[k])
		assert_eq(s.rarity, CHAR_RARITIES[k], "rareté de %s" % CHAR_SKINS[k])
		assert_gte(s.preview.get_height(), 256, "aperçu boutique en grand : %s" % CHAR_SKINS[k])
	# Anciens skins supprimés.
	for old: String in ["night", "neon", "gold"]:
		assert_false(ResourceLoader.exists("res://data/skins/char_%s.tres" % old), "ancien skin encore présent : %s" % old)


func test_hero_skin_repli() -> void:
	assert_eq(HeroSkin.sprite_dir_for(null), HeroSkin.DEFAULT_DIR)
	assert_not_null(HeroSkin.frames_for(null))
	assert_true(HeroSkin.meta_for(null).has("feet_offset"))
	assert_null(HeroSkin.material_for(null))


func test_sprites_et_icones_armes() -> void:
	for wid: String in WEAPON_IDS:
		var png := "res://assets/sprites/weapons/%s.png" % wid
		var tex := load(png) as Texture2D
		assert_not_null(tex, "sprite d'arme manquant : %s" % png)
		var meta := _read_json("res://assets/sprites/weapons/%s.json" % wid)
		assert_false(meta.is_empty(), "json d'arme manquant : %s" % wid)
		if tex != null and not meta.is_empty():
			var g: Array = meta["grip"]
			var m: Array = meta["muzzle"]
			assert_gt(float(meta.get("scale", 0.0)), 0.0)
			assert_true(float(g[0]) >= 0.0 and float(g[0]) <= tex.get_width() and float(g[1]) <= tex.get_height(), "grip dans l'image : %s" % wid)
			assert_gt(float(m[0]), float(g[0]), "canon vers la droite : %s" % wid)
			assert_true(float(m[0]) <= tex.get_width(), "muzzle dans l'image : %s" % wid)
		var icon := load("res://assets/ui/weapons/%s.png" % wid) as Texture2D
		assert_not_null(icon, "icône d'arme manquante : %s" % wid)
		if icon != null:
			# 256 × 128, ou 512 × 256 pour les armes refaites en HD (art/blender/weapons_hd.py).
			assert_true(Vector2i(icon.get_size()) in [Vector2i(256, 128), Vector2i(512, 256)],
				"taille d'icône : %s (%s)" % [wid, icon.get_size()])


func test_sprites_au_sol_des_gadgets() -> void:
	for gid: String in GADGET_IDS:
		var tex := load("res://assets/sprites/weapons/%s_world.png" % gid) as Texture2D
		assert_not_null(tex, "sprite au sol manquant : %s" % gid)
		if tex != null:
			assert_eq(Vector2i(tex.get_size()), Vector2i(64, 64), "taille du sprite au sol : %s" % gid)
	assert_not_null(load("res://assets/sprites/weapons/gadget_drone_world_b.png"), "2e image du drone")


func test_replis_par_categorie() -> void:
	for cat: String in ["pistol", "smg", "rifle", "sniper", "rocket_launcher", "gadget"]:
		assert_true(ResourceLoader.exists("res://assets/ui/weapons/%s.png" % cat), "icône de catégorie : %s" % cat)
		assert_true(ResourceLoader.exists("res://assets/sprites/weapons/%s.png" % cat), "sprite de catégorie : %s" % cat)
