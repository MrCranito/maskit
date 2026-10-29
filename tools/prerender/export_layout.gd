extends SceneTree
## Exporte l'étage 0 (FloorLayout) d'une seed Far West en JSON pour le rendu Blender.
## godot --headless --path . --script res://tools/prerender/export_layout.gd -- <seed> <out.json> [difficulté] [monde.tres]
## (Ajout station) 4e argument : chemin du monde (défaut Far West). Champs génériques ajoutés :
## low_gravity (cases), contract (métadonnée « render_contract » du layout, convertie en JSON).

func _sp(s: FloorLayout.Spawn) -> Dictionary:
	return {"cell": [s.cell.x, s.cell.y], "kind": String(s.kind), "off": [s.offset.x, s.offset.y],
		"size": [s.size.x, s.size.y], "flip": s.flip, "rot": s.rot, "scale": s.scale, "room": s.room_id}

## Lecture tolérante d'une propriété (le générateur peut ne pas encore la fournir).
func _g(o: Object, prop: String, def: Variant) -> Variant:
	if o == null:
		return def
	for p in o.get_property_list():
		if String(p["name"]) == prop:
			var v: Variant = o.get(prop)
			return def if v == null else v
	return def


func _cells(v: Variant) -> Array:
	var out: Array = []
	if v is Dictionary:
		for c in (v as Dictionary).keys():
			if c is Vector2i:
				out.append([c.x, c.y])
	elif v is Array:
		for c in v:
			if c is Vector2i:
				out.append([c.x, c.y])
			elif c is Array and c.size() >= 2:
				out.append([int(c[0]), int(c[1])])
	return out


func _rect(v: Variant) -> Array:
	if v is Rect2i:
		var r: Rect2i = v
		return [r.position.x, r.position.y, r.size.x, r.size.y]
	return v if v is Array else []


## Champs du contrat de rendu (JSON) lus sur FloorLayout s'ils existent, sinon absents
## (fw_scene.py les déduit alors de landmark_spawns / prop_spawns / decor_spawns) :
##   paths: [[x,y]…]  fences: [[[x,y]…]…]  rock_formations: [{cells, height}]
##   props: [{kind, cell, rot, size}]  rails: [[x,y]…]  train: [{kind, rect}]
##   landmarks: [{kind, rect}]  (windmill, water_tower, well…)
func _export_contract(L: FloorLayout, d: Dictionary) -> void:
	var paths: Variant = _g(L, "paths", null)
	if paths != null:
		d["paths"] = _cells(paths)
	var fences: Variant = _g(L, "fences", null)
	if fences is Array:
		var fl: Array = []
		for line in fences:
			fl.append(_cells(line))
		d["fences"] = fl
	var rocks: Variant = _g(L, "rock_formations", null)
	if rocks is Array:
		var rl: Array = []
		for r in rocks:
			if r is Dictionary:
				rl.append({"cells": _cells(r.get("cells", [])), "height": float(r.get("height", 1.6)),
					"kind": String(r.get("kind", "mesa"))})
			elif r is Object:
				rl.append({"cells": _cells(_g(r, "cells", [])), "height": float(_g(r, "height", 1.6))})
		d["rock_formations"] = rl
	var props: Variant = _g(L, "props", null)
	if props is Array:
		var pl: Array = []
		for p in props:
			if p is FloorLayout.Spawn:
				var s: FloorLayout.Spawn = p
				pl.append({"kind": String(s.kind), "cell": [s.cell.x, s.cell.y], "rot": s.rot,
					"size": [s.size.x, s.size.y], "off": [s.offset.x, s.offset.y]})
			elif p is Dictionary:
				var c: Variant = p.get("cell", Vector2i.ZERO)
				pl.append({"kind": String(p.get("kind", "")), "cell": [c.x, c.y] if c is Vector2i else c,
					"rot": float(p.get("rot", 0.0)), "size": _cells([p.get("size", Vector2i.ONE)])[0] if p.get("size") is Vector2i else p.get("size", [1, 1])})
		d["props"] = pl
	# Voies : polylignes {kind, points, width} → cases de l'axe (rails) + liste brute (rail_lines).
	var rails: Variant = _g(L, "rails", null)
	if rails is Array and not (rails as Array).is_empty():
		var cells: Array = []
		var lines: Array = []
		for r in rails:
			if r is Dictionary:
				var pts: Array = _cells(r.get("points", []))
				lines.append({"kind": String(r.get("kind", "main")), "points": pts, "width": int(r.get("width", 3))})
				for i in range(pts.size() - 1):
					var a: Array = pts[i]
					var b: Array = pts[i + 1]
					var n := maxi(absi(b[0] - a[0]), absi(b[1] - a[1]))
					for k in n + 1:
						var c := [a[0] + signi(b[0] - a[0]) * k, a[1] + signi(b[1] - a[1]) * k]
						if not cells.has(c):
							cells.append(c)
			elif r is Vector2i:
				cells.append([r.x, r.y])
		d["rails"] = cells
		d["rail_lines"] = lines
	for key in ["train", "landmarks"]:
		var arr: Variant = _g(L, key, null)
		if arr is Array:
			var out: Array = []
			for e in arr:
				if e is Dictionary:
					var k := String(e.get("kind", ""))
					if k.begins_with("lm_"):
						k = k.substr(3)
					if k == "prop_water_tower":
						k = "water_tower"
					out.append({"kind": k, "rect": _rect(e.get("rect", []))})
				elif e is FloorLayout.Spawn:
					var sp: FloorLayout.Spawn = e
					out.append({"kind": String(sp.kind), "rect": [sp.cell.x - (sp.size.x - 1) / 2, sp.cell.y - sp.size.y + 1, sp.size.x, sp.size.y]})
			d[key] = out


## Conversion récursive des types Godot (Vector2i, Rect2i, Vector2…) en types JSON.
func _json(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in (v as Dictionary).keys():
			o[String(k)] = _json(v[k])
		return o
	if v is Array:
		var l: Array = []
		for e: Variant in v:
			l.append(_json(e))
		return l
	if v is Vector2i or v is Vector2:
		return [v.x, v.y]
	if v is Rect2i or v is Rect2:
		return [v.position.x, v.position.y, v.size.x, v.size.y]
	if v is StringName:
		return String(v)
	return v


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var world_path := String(a[3]) if a.size() > 3 and String(a[3]) != "" else "res://data/worlds/world_01_far_west.tres"
	var world: WorldData = load(world_path)
	var gen: Script = load(world.generator_path)
	# Même appel que le raid (generate_run, difficulté par défaut) : le plan doit être identique
	# au tuile près (empreinte tiles_md5 vérifiée en jeu par PrerenderBackdrop).
	var cfg := ConfigFile.new()
	cfg.load("res://data/balance.cfg")
	var diff := int(a[2]) if a.size() > 2 and String(a[2]) != "" else int(cfg.get_value("raid", "default_difficulty", 1))
	var L: FloorLayout = null
	for l: FloorLayout in gen.call("generate_run", int(a[0]), world, diff):
		if l.floor_index == 0:
			L = l
	var d := {"seed": int(a[0]), "size": [L.size.x, L.size.y], "tile": FloorLayout.TILE_SIZE}
	var rows: Array = []
	for y in L.size.y:
		var line := ""
		for x in L.size.x:
			line += str(L.get_tile(Vector2i(x, y)))
		rows.append(line)
	d["tiles"] = rows
	var bl: Array = []
	for b in L.buildings:
		var doors: Array = []
		for did in b.door_ids:
			var dd := L.doors[did]
			var ra := L.get_room(dd.room_a)
			var rb := L.get_room(dd.room_b)
			doors.append({"cell": [dd.cell.x, dd.cell.y], "vertical": dd.vertical,
				"outside": (ra != null and ra.outdoor) or (rb != null and rb.outdoor)})
		var be := {"id": b.id, "arch": String(b.archetype), "name": b.name,
			"rect": [b.rect.position.x, b.rect.position.y, b.rect.size.x, b.rect.size.y], "doors": doors}
		# Champs du contrat de rendu (optionnels, remplis par le générateur s'ils existent) :
		# roof_style (tin_blue | tin_rust | tin_grey | shingle | red | plank), stories (1|2),
		# porch_side (N|S|E|W). Absents → fw_scene.py choisit (seed) / déduit des portes.
		be["roof_style"] = String(_g(b, "roof_style", ""))
		be["stories"] = int(_g(b, "stories", 2 if String(b.archetype) in ["saloon", "hotel"] else 1))
		var ps: Variant = _g(b, "porch_side", "")
		if ps is Vector2i:
			var v: Vector2i = ps
			ps = "S" if v == Vector2i.DOWN else "N" if v == Vector2i.UP else "W" if v == Vector2i.LEFT else "E" if v == Vector2i.RIGHT else ""
		be["porch_side"] = String(ps)
		bl.append(be)
	d["buildings"] = bl
	var dl: Array = []
	for dd2 in L.doors:
		dl.append({"cell": [dd2.cell.x, dd2.cell.y], "vertical": dd2.vertical, "state": dd2.state})
	d["doors"] = dl
	var rl: Array = []
	for r in L.rooms:
		rl.append({"id": r.id, "rect": [r.rect.position.x, r.rect.position.y, r.rect.size.x, r.rect.size.y],
			"outdoor": r.outdoor, "b": r.building_id, "tags": Array(r.tags)})
	d["rooms"] = rl
	for key in ["landmark_spawns", "prop_spawns", "container_spawns", "hiding_spot_spawns", "decor_spawns"]:
		var arr: Array = []
		for s: FloorLayout.Spawn in L.get(key):
			arr.append(_sp(s))
		d[key] = arr
	var st: Array = []
	for s2 in L.stairs:
		st.append({"cell": [s2.cell.x, s2.cell.y], "up": s2.up})
	d["stairs"] = st
	var pc: Array = []
	for c: Vector2i in L.partition_cells:
		pc.append([c.x, c.y])
	d["partition"] = pc
	var ex: Array = []
	for c2 in L.extraction_cells:
		ex.append([c2.x, c2.y])
	d["extraction"] = ex
	d["player_spawn"] = [L.player_spawn.x, L.player_spawn.y]
	_export_contract(L, d)
	# (Ajout station) Gravité faible et contrat de rendu propre au biome (métadonnée du layout).
	d["low_gravity"] = _cells(L.low_gravity_cells)
	d["biome"] = String(world.biome)
	d["floor_names"] = {"0": String(world.floor_names.get(0, ""))}
	if L.has_meta(&"render_contract"):
		d["contract"] = _json(L.get_meta(&"render_contract"))
	var f := FileAccess.open(a[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("EXPORTED ", a[1], " ", L.size, " buildings=", L.buildings.size())
	quit()
