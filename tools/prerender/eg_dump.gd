extends SceneTree
## Aperçu du plan de la surface égyptienne : ASCII + stats + PNG (8 px/case).

func _initialize() -> void:
	print("START")
	var a := OS.get_cmdline_user_args()
	var seed_v := int(a[0]) if a.size() > 0 else 1
	var out := String(a[1]) if a.size() > 1 else "/tmp/eg_plan.png"
	var world: WorldData = load("res://data/worlds/world_06_egypt_pyramids.tres")
	var t0 := Time.get_ticks_usec()
	var floors := EgyptGenerator.generate_run(seed_v, world, 2)
	print("gen ms ", (Time.get_ticks_usec() - t0) / 1000.0)
	if floors.is_empty():
		print("ECHEC")
		quit(1)
		return
	var L := floors[0]
	var cells := {}
	for d in L.doors:
		cells[d.cell] = "L" if d.state == FloorLayout.DoorState.LOCKED else "D"
	for s in L.enemy_spawns:
		cells[s.cell] = "e"
	for s2 in L.container_spawns:
		cells[s2.cell] = "c"
	for s3 in L.hiding_spot_spawns:
		cells[s3.cell] = "h"
	for s4 in L.prop_spawns:
		cells[s4.cell] = "p"
	for e in L.extraction_cells:
		cells[e] = "X"
	cells[L.player_spawn] = "@"
	var img := Image.create(L.size.x * 8, L.size.y * 8, false, Image.FORMAT_RGB8)
	for y in L.size.y:
		var line := ""
		for x in L.size.x:
			var c := Vector2i(x, y)
			var t := L.get_tile(c)
			var ch := " "
			var col := Color(0.9, 0.75, 0.45)
			match t:
				FloorLayout.Tile.WALL:
					ch = "#"
					col = Color(0.45, 0.3, 0.18)
				FloorLayout.Tile.FLOOR:
					ch = "."
					col = Color(0.75, 0.6, 0.4)
				FloorLayout.Tile.STREET:
					ch = " "
				FloorLayout.Tile.DOOR:
					ch = "D"
					col = Color(0.2, 0.4, 1.0)
			var r := L.room_at(c)
			if r != null and r.building_id >= 0 and t == FloorLayout.Tile.FLOOR:
				col = Color(0.6, 0.45, 0.35)
			if cells.has(c):
				ch = cells[c]
				match ch:
					"e": col = Color(1, 0.2, 0.2)
					"c": col = Color(1, 0.9, 0.2)
					"h": col = Color(0.2, 0.9, 0.9)
					"p": col = Color(0.3, 0.7, 0.3)
					"X": col = Color(0.2, 1, 0.4)
					"@": col = Color(1, 1, 1)
					"L": col = Color(1, 0, 1)
			line += ch
			img.fill_rect(Rect2i(x * 8, y * 8, 8, 8), col)
		print(line)
	img.save_png(out)
	print("rooms ", L.rooms.size(), " buildings ", L.buildings.size(), " doors ", L.doors.size(), " enemies ", L.enemy_spawns.size(),
		" containers ", L.container_spawns.size(), " hides ", L.hiding_spot_spawns.size(), " props ", L.prop_spawns.size())
	var reach := L.flood_reachable(L.player_spawn, true)
	var missing := 0
	for y2 in L.size.y:
		for x2 in L.size.x:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x2, y2))) and not reach.has(Vector2i(x2, y2)):
				missing += 1
	print("unreachable ", missing)
	for r2 in L.rooms:
		if r2.type == FloorLayout.ROOM_SUPER_LOOT or r2.type == FloorLayout.ROOM_BOSS:
			print(r2.type, " ", r2.name, " ", r2.rect)
	quit()
