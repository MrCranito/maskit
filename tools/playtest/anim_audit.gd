extends Node
## Volet 4 — audit des animations des monstres (planches EnemyArt), sans jouer.
##   godot --headless --path . -s res://tools/playtest/anim_audit_main.gd -- --out=DOSSIER
## Pour chaque kind de assets/sprites/enemies/<kind>/ :
##  - animations attendues (idle, run, attack, hit, death × 8 directions) : manquantes ou vides ;
##  - nombre d'images et cadence (meta.json) ;
##  - pieds : écart horizontal de la colonne des pieds d'une image de course à l'autre (glisse,
##    personnage décentré) et écart vertical au point d'appui déclaré (flotte / s'enfonce) ;
##  - image finale de la mort (cadavre) présente ;
##  - ressemblance : couleurs moyennes de la pose de repos face caméra, comparées entre monstres
##    d'un même monde (paires trop proches = risque de confusion sur téléphone) ;
##  - hauteur affichée (lisibilité sur téléphone).
## Sorties : <out>/audit_animations.json et une planche PNG par monde (repos, course ×4,
## armement, coup, touché, cadavre — direction sud-est).

const DIR := "res://assets/sprites/enemies/"
const ANIMS := ["idle", "run", "attack", "hit", "death"]
const DIRS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const CELL := 128

var out_dir: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var report := {}
	var by_world := {}
	for kind: String in DirAccess.get_directories_at(DIR):
		var fpath := DIR + kind + "/" + kind + "_frames.tres"
		var mpath := DIR + kind + "/" + kind + "_meta.json"
		if not ResourceLoader.exists(fpath):
			report[kind] = {"erreur": "planche absente"}
			continue
		var sf := load(fpath) as SpriteFrames
		var meta: Dictionary = {}
		if FileAccess.file_exists(mpath):
			var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(mpath))
			meta = m if m is Dictionary else {}
		print("audit ", kind)
		report[kind] = _audit(kind, sf, meta)
		var w := kind.get_slice("_", 0)
		(by_world.get_or_add(w, []) as Array).append(kind)
	# Ressemblance dans chaque monde.
	var sims := []
	for w: String in by_world:
		var kinds: Array = by_world[w]
		for i in kinds.size():
			for j in range(i + 1, kinds.size()):
				var a: Array = report[kinds[i]].get("_sig", [])
				var b: Array = report[kinds[j]].get("_sig", [])
				if a.is_empty() or b.is_empty():
					continue
				var d := 0.0
				for k in a.size():
					d += absf(float(a[k]) - float(b[k]))
				sims.append({"a": kinds[i], "b": kinds[j], "distance": snappedf(d / a.size(), 0.001),
					"hauteurs": [report[kinds[i]].get("height_px", 0), report[kinds[j]].get("height_px", 0)]})
		_board(w, kinds)
	sims.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["distance"] < y["distance"])
	for k: String in report:
		report[k].erase("_sig")
	var fo := FileAccess.open(out_dir.path_join("audit_animations.json"), FileAccess.WRITE)
	fo.store_string(JSON.stringify({"kinds": report, "ressemblances": sims}, "  "))
	fo.close()
	print("AUDIT ok")
	get_tree().quit(0)


func _audit(kind: String, sf: SpriteFrames, meta: Dictionary) -> Dictionary:
	var r := {"missing": [], "frames": {}, "fps": meta.get("fps", {}), "height_px": meta.get("height_px", 0),
		"display_height": meta.get("display_height", 0)}
	var feet: Array = meta.get("feet_offset", [0, 0])
	for an: String in ANIMS:
		var counts := {}
		for d: String in DIRS:
			var name := "%s_%s" % [an, d]
			if not sf.has_animation(name):
				(r["missing"] as Array).append(name)
				continue
			counts[d] = sf.get_frame_count(name)
			if sf.get_frame_count(name) == 0:
				(r["missing"] as Array).append(name + " (vide)")
		r["frames"][an] = counts.values().min() if not counts.is_empty() else 0
		if not counts.is_empty() and counts.values().min() != counts.values().max():
			r["frames_inegales_" + an] = counts
	# Pieds pendant la course, dans 4 directions.
	var drift := 0.0
	var sink := 0.0
	var n := 0
	for d2: String in ["se", "sw", "e", "s"]:
		var name2 := "run_" + d2
		if not sf.has_animation(name2):
			continue
		var xs := []
		for i in sf.get_frame_count(name2):
			var img := _img(sf.get_frame_texture(name2, i))
			if img == null:
				continue
			var fb := _feet(img)
			if fb.x < 0.0:
				continue
			xs.append(fb.x)
			if feet.size() >= 2:
				sink = maxf(sink, absf(fb.y - float(feet[1])))
				n += 1
		if xs.size() >= 2:
			drift = maxf(drift, float(xs.max()) - float(xs.min()))
	r["pieds_ecart_horizontal_px"] = snappedf(drift, 0.1)
	r["pieds_ecart_appui_px"] = snappedf(sink, 0.1)
	# Cadavre : dernière image de la mort non vide.
	if sf.has_animation("death_se") and sf.get_frame_count("death_se") > 0:
		var last := _img(sf.get_frame_texture("death_se", sf.get_frame_count("death_se") - 1))
		r["cadavre"] = last != null and last.get_used_rect().size != Vector2i.ZERO
	# Signature de couleur (repos, sud).
	var idle := _img(sf.get_frame_texture("idle_s", 0)) if sf.has_animation("idle_s") else null
	if idle != null:
		r["_sig"] = _signature(idle)
	return r


static var _atlas_cache: Dictionary = {}


## Image d'une image de planche : région de l'atlas PNG source (les textures importées sont
## compressées pour la carte graphique et illisibles en headless).
static func _img(t: Texture2D) -> Image:
	if t == null:
		return null
	if t is AtlasTexture:
		var at := t as AtlasTexture
		var path := at.atlas.resource_path if at.atlas != null else ""
		if path.is_empty():
			return null
		if not _atlas_cache.has(path):
			var src := Image.load_from_file(ProjectSettings.globalize_path(path))
			if src != null:
				src.convert(Image.FORMAT_RGBA8)
			_atlas_cache[path] = src
		var full: Image = _atlas_cache[path]
		if full == null:
			return null
		var r := Rect2i(at.region)
		var out := Image.create(r.size.x + int(at.margin.size.x), r.size.y + int(at.margin.size.y), false, Image.FORMAT_RGBA8)
		out.blit_rect(full, r, Vector2i(at.margin.position))
		return out
	var img := t.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Centre horizontal et bas des pixels opaques de la bande des pieds (6 px du bas de l'emprise).
static func _feet(img: Image) -> Vector2:
	var ur := img.get_used_rect()
	if ur.size.y <= 0:
		return Vector2(-1, -1)
	var bottom := ur.end.y - 1
	var sx := 0.0
	var cnt := 0
	for y in range(maxi(bottom - 6, ur.position.y), bottom + 1):
		for x in range(ur.position.x, ur.end.x):
			if img.get_pixel(x, y).a > 0.5:
				sx += x
				cnt += 1
	return Vector2(sx / maxf(cnt, 1), bottom) if cnt > 0 else Vector2(-1, -1)


static func _signature(img: Image) -> Array:
	var ur := img.get_used_rect()
	var c := img.get_region(ur)
	c.resize(6, 8, Image.INTERPOLATE_BILINEAR)
	var out := []
	for y in 8:
		for x in 6:
			var p := c.get_pixel(x, y)
			out.append_array([p.r * p.a, p.g * p.a, p.b * p.a])
	return out


## Planche du monde : une ligne par monstre, direction sud-est.
func _board(world: String, kinds: Array) -> void:
	var cols := [["idle_se", 0], ["run_se", 0], ["run_se", 2], ["run_se", 4], ["run_se", 6],
		["attack_se", 2], ["attack_se", 3], ["hit_se", 1], ["death_se", -1]]
	var img := Image.create(CELL * cols.size(), CELL * kinds.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.93, 0.9))
	for i in kinds.size():
		var sf := load(DIR + kinds[i] + "/" + kinds[i] + "_frames.tres") as SpriteFrames
		for j in cols.size():
			var an: String = cols[j][0]
			if not sf.has_animation(an) or sf.get_frame_count(an) == 0:
				continue
			var fi: int = cols[j][1]
			if fi < 0 or fi >= sf.get_frame_count(an):
				fi = sf.get_frame_count(an) - 1
			var fr := _img(sf.get_frame_texture(an, fi))
			if fr == null:
				continue
			fr.convert(Image.FORMAT_RGBA8)
			var s := float(CELL) / maxf(fr.get_width(), fr.get_height())
			fr.resize(maxi(1, int(fr.get_width() * s)), maxi(1, int(fr.get_height() * s)), Image.INTERPOLATE_BILINEAR)
			img.blend_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(j * CELL + (CELL - fr.get_width()) / 2, i * CELL + (CELL - fr.get_height()) / 2))
	img.save_png(out_dir.path_join("planche_%s.png" % world))
