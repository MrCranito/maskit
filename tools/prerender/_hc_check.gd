extends SceneTree
## Vérification rapide du plan du Carnaval : ASCII + stats.

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_v := int(a[0]) if a.size() > 0 else 2025
	var world: WorldData = load("res://data/worlds/world_04_haunted_carnival.tres")
	var gen: Script = load("res://scripts/biomes/haunted_carnival/hc_generator.gd")
	var t0 := Time.get_ticks_usec()
	var floors: Array = gen.call("generate_run", seed_v, world, 2)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if floors.is_empty():
		print("ECHEC")
		quit(1)
		return
	var L: FloorLayout = floors[0]
	var ch := {0: " ", 1: ".", 2: ":", 3: "#", 4: "D", 5: "<", 6: ">"}
	var marks := {}
	for e in L.enemy_spawns:
		marks[e.cell] = "e"
	for c in L.container_spawns:
		marks[c.cell] = "c"
	for h in L.hiding_spot_spawns:
		marks[h.cell] = "h"
	for p in L.prop_spawns:
		marks[p.cell] = "p"
	for x in L.extraction_cells:
		marks[x] = "X"
	marks[L.player_spawn] = "@"
	var out := ""
	for y in L.size.y:
		var line := ""
		for x in L.size.x:
			var c := Vector2i(x, y)
			line += marks.get(c, ch[L.get_tile(c)])
		out += line + "\n"
	var f := FileAccess.open(a[1] if a.size() > 1 else "/tmp/hc_plan.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("ms=", ms, " rooms=", L.rooms.size(), " bld=", L.buildings.size(), " doors=", L.doors.size(), " enemies=", L.enemy_spawns.size(),
		" cont=", L.container_spawns.size(), " hide=", L.hiding_spot_spawns.size(), " props=", L.prop_spawns.size(), " extr=", L.extraction_cells.size())
	var reach := L.flood_reachable(L.player_spawn, true)
	var miss := 0
	for y2 in L.size.y:
		for x2 in L.size.x:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x2, y2))) and not reach.has(Vector2i(x2, y2)):
				miss += 1
	print("unreachable=", miss)
	for r in L.rooms:
		if r.type == FloorLayout.ROOM_BOSS or r.type == FloorLayout.ROOM_SUPER_LOOT:
			var n := 0
			for e2 in L.enemy_spawns:
				if e2.room_id == r.id:
					n += 1
			print(r.name, " type=", r.type, " enemies=", n)
	quit()
