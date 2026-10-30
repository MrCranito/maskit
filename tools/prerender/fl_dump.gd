extends SceneTree
## Aperçu ASCII + statistiques de l'étage 0 des Terres gelées (développement) :
##   godot --headless --path . --script res://tools/prerender/fl_dump.gd -- <seed> [out.png]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_value := int(a[0]) if a.size() > 0 else 1
	var world: WorldData = load("res://data/worlds/world_05_frozen_lands.tres")
	var gen: Script = load(world.generator_path)
	var t0 := Time.get_ticks_usec()
	var floors: Array = gen.call("generate_run", seed_value, world, 1)
	var dt := (Time.get_ticks_usec() - t0) / 1000.0
	if floors.is_empty():
		print("ECHEC")
		quit(1)
		return
	var L: FloorLayout = floors[0]
	var ch := {0: " ", 1: ".", 2: ":", 3: "#", 4: "D", 5: "<", 6: ">"}
	var grid: Array = []
	for y in L.size.y:
		var row: PackedStringArray = []
		for x in L.size.x:
			row.append(ch[L.get_tile(Vector2i(x, y))])
		grid.append(row)
	for s in L.prop_spawns:
		grid[s.cell.y][s.cell.x] = "p"
	for s2 in L.container_spawns:
		grid[s2.cell.y][s2.cell.x] = "c"
	for s3 in L.hiding_spot_spawns:
		grid[s3.cell.y][s3.cell.x] = "h"
	for s4 in L.enemy_spawns:
		grid[s4.cell.y][s4.cell.x] = "e"
	for e in L.extraction_cells:
		grid[e.y][e.x] = "X"
	grid[L.player_spawn.y][L.player_spawn.x] = "S"
	for d in L.doors:
		grid[d.cell.y][d.cell.x] = "L" if d.state == FloorLayout.DoorState.LOCKED else "D"
	for y2 in L.size.y:
		print("%3d %s" % [y2, "".join(grid[y2])])
	print("seed %d  %.1f ms  rooms %d buildings %d doors %d props %d containers %d hides %d enemies %d extraction %d" % [
		seed_value, dt, L.rooms.size(), L.buildings.size(), L.doors.size(), L.prop_spawns.size(),
		L.container_spawns.size(), L.hiding_spot_spawns.size(), L.enemy_spawns.size(), L.extraction_cells.size()])
	for r in L.rooms:
		print("  room %2d %-34s %-11s %s b=%d" % [r.id, r.name, r.type, r.rect, r.building_id])
	quit()
