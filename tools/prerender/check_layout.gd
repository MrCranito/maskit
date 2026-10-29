extends SceneTree
## Contrôle de cohérence plan ↔ rendu pré-calculé (Far West, étage 0).
##   godot --headless --path . --script res://tools/prerender/check_layout.gd -- \
##       <seed> <pack_dir|full.png> <mask.png> <out.png> [out.json] [ppc_out=24]
## - régénère l'étage 0 de la seed (même appel que le raid / export_layout.gd) ;
## - fond : rendu pré-calculé (tuiles du paquet map.json, ou full.png), réduit à ppc_out px/case
##   (sol z = 0 exactement sur la grille, cf. prerender_backdrop.gd) ;
## - superpose : cases bloquantes du layout (WALL / VOID, rouge translucide ; props, conteneurs,
##   cachettes : rouge clair), portes (bleu ; magenta = porte cachée sous un toit), escaliers
##   (jaune), contour de l'emprise RÉELLE des objets rendus (masque zénithal de
##   fw_scene.py « mask », 4 px/case : blanc = obstacle du plan, vert = fouillis décoratif) ;
## - compare par case : « rendu bloquant mais praticable » (orange plein) et « bloquant mais rien
##   de rendu » (cyan) ; liste les cases dans out.json (et un résumé sur la sortie standard) ;
## - paquet avec couche « emprise rendue » (map.json collision) : rectangles en jaune, et liste des
##   cases rendues bloquantes que ni le plan ni cette couche ne bloquent (render_solid_still_walkable).
## Une case est « rendue bloquante » si au moins [mask_cov] (25 %) de ses pixels de masque sont
## allumés (canal R ou G > 127).

const MASK_PPC := 4
const COV_SOLID := 0.25
const COV_EMPTY := 0.06


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("usage : <seed> <pack_dir|full.png> <mask.png> <out.png> [out.json] [ppc_out]")
		quit(1)
		return
	var seed_value := int(a[0])
	var ppc_out := int(a[5]) if a.size() > 5 else 24
	var L := _generate(seed_value)
	var info := {}
	var bg := _load_backdrop(a[1], info)
	if bg == null:
		push_error("fond introuvable : " + a[1])
		quit(1)
		return
	var M := int(info.get("margin", 4))
	var ppc_in := int(info.get("ppc", 72))
	var tilt := float(info.get("tilt_deg", 38.0))
	var tw := L.size.x + 2 * M
	var th := L.size.y + 2 * M
	bg.resize(tw * ppc_out, th * ppc_out, Image.INTERPOLATE_BILINEAR)
	bg.convert(Image.FORMAT_RGBA8)
	var mask := Image.load_from_file(a[2])
	if mask != null:
		mask.convert(Image.FORMAT_RGB8)
	var rep := compare(L, mask, M)
	# Couche « emprise rendue » du paquet (map.json collision) : cases rendues bloquantes encore
	# praticables en jeu = ni murées dans le plan, ni couvertes (≥ 25 %) par cette couche.
	var coll: Array = info.get("collision", [])
	var cov := {}
	for r: Array in coll:
		var rr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		for y in range(floori(rr.position.y / 64.0), ceili(rr.end.y / 64.0)):
			for x in range(floori(rr.position.x / 64.0), ceili(rr.end.x / 64.0)):
				var k := Vector2i(x, y)
				cov[k] = float(cov.get(k, 0.0)) + Rect2(x * 64.0, y * 64.0, 64.0, 64.0).intersection(rr).get_area() / 4096.0
	var still: Array = []
	for e: Array in rep["render_solid_walkable"]:
		if float(cov.get(Vector2i(int(e[0]), int(e[1])), 0.0)) < 0.25:
			still.append(e)
	rep["render_solid_still_walkable"] = still
	rep["collision_rects"] = coll.size()
	_draw(bg, L, mask, rep, M, ppc_out, tilt)
	for r2: Array in coll:
		var px := Rect2i(Vector2i((Vector2(float(r2[0]), float(r2[1])) / 64.0 + Vector2(M, M)) * ppc_out),
			Vector2i(maxi(int(float(r2[2]) / 64.0 * ppc_out), 1), maxi(int(float(r2[3]) / 64.0 * ppc_out), 1)))
		_fill(bg, px, Color(1, 0.9, 0.1, 0.45))
	bg.save_png(a[3])
	if a.size() > 4 and a[4] != "":
		var f := FileAccess.open(a[4], FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, " "))
		f.close()
	print("CHECK seed=%d render_solid_walkable=%d (sans collision du paquet : %d, rectangles %d) blocked_not_rendered=%d hidden_doors=%d/%d" % [seed_value,
		(rep["render_solid_walkable"] as Array).size(), (rep["render_solid_still_walkable"] as Array).size(), int(rep["collision_rects"]),
		(rep["blocked_not_rendered"] as Array).size(), (rep["hidden_doors"] as Array).size(), int(rep["outside_doors"])])
	for k: String in ["render_solid_still_walkable", "blocked_not_rendered", "hidden_doors"]:
		print("  ", k, " : ", JSON.stringify(rep[k]).left(1600))
	quit()


static func _generate(seed_value: int) -> FloorLayout:
	var world: WorldData = load("res://data/worlds/world_01_far_west.tres")
	var gen: Script = load(world.generator_path)
	var cfg := ConfigFile.new()
	cfg.load("res://data/balance.cfg")
	var diff := int(cfg.get_value("raid", "default_difficulty", 1))
	for l: FloorLayout in gen.call("generate_run", seed_value, world, diff):
		if l.floor_index == 0:
			return l
	return null


## Image complète du rendu : full.png, ou recomposée depuis les tuiles d'un paquet (map.json).
static func _load_backdrop(path: String, info: Dictionary) -> Image:
	if path.ends_with(".png"):
		var rj := path.get_base_dir().path_join("render.json")
		if FileAccess.file_exists(rj):
			info.merge(JSON.parse_string(FileAccess.get_file_as_string(rj)), true)
		return Image.load_from_file(path)
	var mj := path.path_join("map.json")
	if not FileAccess.file_exists(mj):
		return null
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mj))
	info.merge(meta, true)
	var px: Array = meta["image_px"]
	var img := Image.create(int(px[0]), int(px[1]), false, Image.FORMAT_RGB8)
	for t: Dictionary in meta["tiles"]:
		var ti := Image.load_from_file(ProjectSettings.globalize_path(path.path_join(String(t["file"]))))
		if ti == null:
			continue
		ti.convert(Image.FORMAT_RGB8)
		var p: Array = t["px"]
		img.blit_rect(ti, Rect2i(0, 0, ti.get_width(), ti.get_height()), Vector2i(int(p[0]), int(p[1])))
	return img


## Cases bloquantes « gameplay » : WALL / VOID + emprises des props / conteneurs / cachettes.
static func blocked_cells(L: FloorLayout) -> Dictionary:
	var out := {}
	for y in L.size.y:
		for x in L.size.x:
			var c := Vector2i(x, y)
			if not FloorLayout.is_walkable_tile(L.get_tile(c)):
				out[c] = 1
	for key in ["prop_spawns", "container_spawns", "hiding_spot_spawns"]:
		for s: FloorLayout.Spawn in L.get(key):
			for c2 in FloorLayout.spawn_cells(s):
				if not out.has(c2):
					out[c2] = 2
	return out


## Couverture (0..1) du masque sur la case c (canal R = obstacle du plan, G = fouillis).
static func cell_cov(mask: Image, c: Vector2i, M: int) -> Vector2:
	if mask == null:
		return Vector2.ZERO
	var x0 := (c.x + M) * MASK_PPC
	var y0 := (c.y + M) * MASK_PPC
	var r := 0
	var g := 0
	for dy in MASK_PPC:
		for dx in MASK_PPC:
			var px := mask.get_pixel(x0 + dx, y0 + dy)
			if px.r > 0.5:
				r += 1
			if px.g > 0.5 or px.r > 0.5:
				g += 1
	var n := float(MASK_PPC * MASK_PPC)
	return Vector2(r / n, g / n)


static func compare(L: FloorLayout, mask: Image, M: int) -> Dictionary:
	var blocked := blocked_cells(L)
	var solid_walk: Array = []
	var empty_block: Array = []
	if mask != null:
		for y in L.size.y:
			for x in L.size.x:
				var c := Vector2i(x, y)
				var cov := cell_cov(mask, c, M)
				var t := L.get_tile(c)
				if cov.y >= COV_SOLID and not blocked.has(c):
					solid_walk.append([x, y, snappedf(cov.y, 0.01), "decor" if cov.x < COV_SOLID else "plan"])
				# Murs de bâtiment : épaisseur rendue 0,42 case (couverture ~0,4) → seuls les
				# obstacles hors bâtiment sont testés « vides ».
				if t == FloorLayout.Tile.WALL and cov.y < COV_EMPTY and _building_at(L, c) < 0 \
						and x > 0 and y > 0 and x < L.size.x - 1 and y < L.size.y - 1:
					empty_block.append([x, y])
	var hidden: Array = []
	var n_out := 0
	for b in L.buildings:
		for did in b.door_ids:
			var d := L.doors[did]
			var side := door_side(b, d)
			if side == "":
				continue
			n_out += 1
			if side != "S":
				hidden.append({"cell": [d.cell.x, d.cell.y], "side": side, "building": b.id, "arch": String(b.archetype)})
	return {"render_solid_walkable": solid_walk, "blocked_not_rendered": empty_block, "hidden_doors": hidden,
		"outside_doors": n_out}


static func _building_at(L: FloorLayout, c: Vector2i) -> int:
	for b in L.buildings:
		if b.rect.has_point(c):
			return b.id
	return -1


## Côté (N/S/E/W) d'une porte du mur d'enceinte du bâtiment, "" pour une porte intérieure.
static func door_side(b: FloorLayout.Building, d: FloorLayout.Door) -> String:
	var r := b.rect
	if d.cell.y == r.end.y - 1 and not d.vertical:
		return "S"
	if d.cell.y == r.position.y and not d.vertical:
		return "N"
	if d.cell.x == r.position.x and d.vertical:
		return "W"
	if d.cell.x == r.end.x - 1 and d.vertical:
		return "E"
	return ""


static func _fill(img: Image, r: Rect2i, col: Color) -> void:
	var bl := Image.create(maxi(r.size.x, 1), maxi(r.size.y, 1), false, Image.FORMAT_RGBA8)
	bl.fill(col)
	img.blend_rect(bl, Rect2i(Vector2i.ZERO, bl.get_size()), r.position)


static func _frame(img: Image, r: Rect2i, col: Color, w: int = 2) -> void:
	_fill(img, Rect2i(r.position, Vector2i(r.size.x, w)), col)
	_fill(img, Rect2i(r.position + Vector2i(0, r.size.y - w), Vector2i(r.size.x, w)), col)
	_fill(img, Rect2i(r.position, Vector2i(w, r.size.y)), col)
	_fill(img, Rect2i(r.position + Vector2i(r.size.x - w, 0), Vector2i(w, r.size.y)), col)


static func _draw(img: Image, L: FloorLayout, mask: Image, rep: Dictionary, M: int, p: int, tilt: float) -> void:
	var blocked := blocked_cells(L)
	var cr := func(c: Vector2i) -> Rect2i: return Rect2i((c + Vector2i(M, M)) * p, Vector2i(p, p))
	for c: Vector2i in blocked.keys():
		if L.get_tile(c) == FloorLayout.Tile.VOID:
			continue
		_fill(img, cr.call(c), Color(1, 0.1, 0.1, 0.33) if blocked[c] == 1 else Color(1, 0.55, 0.55, 0.3))
	# Contour de l'emprise rendue (pixels de masque dont un voisin est éteint).
	if mask != null:
		var k := float(p) / MASK_PPC
		for y in range(1, mask.get_height() - 1):
			for x in range(1, mask.get_width() - 1):
				var v := mask.get_pixel(x, y)
				var on := v.r > 0.5 or v.g > 0.5
				if not on:
					continue
				var edge := false
				for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var w := mask.get_pixel(x + n.x, y + n.y)
					if w.r <= 0.5 and w.g <= 0.5:
						edge = true
				if edge:
					var col := Color(1, 1, 1, 0.9) if v.r > 0.5 else Color(0.3, 1, 0.3, 0.9)
					_fill(img, Rect2i(Vector2i(int(x * k), int(y * k)), Vector2i(maxi(int(k), 2), maxi(int(k), 2))), col)
	for e: Array in rep["render_solid_walkable"]:
		var c2 := Vector2i(int(e[0]), int(e[1]))
		_fill(img, cr.call(c2), Color(1, 0.55, 0, 0.6))
		_frame(img, cr.call(c2), Color(1, 0.4, 0, 1), 2)
	for e2: Array in rep["blocked_not_rendered"]:
		_frame(img, cr.call(Vector2i(int(e2[0]), int(e2[1]))), Color(0, 1, 1, 1), 3)
	var hid := {}
	for h: Dictionary in rep["hidden_doors"]:
		hid[Vector2i(int(h["cell"][0]), int(h["cell"][1]))] = true
	for d in L.doors:
		_fill(img, cr.call(d.cell), Color(1, 0, 1, 0.75) if hid.has(d.cell) else Color(0.15, 0.4, 1, 0.7))
	for s in L.stairs:
		_fill(img, cr.call(s.cell), Color(1, 0.9, 0.1, 0.7))
