extends SceneTree
func _initialize() -> void:
	var world: WorldData = load("res://data/worlds/world_04_haunted_carnival.tres")
	var Plan = load("res://scripts/biomes/haunted_carnival/hc_plan.gd")
	var Pop = load("res://scripts/biomes/haunted_carnival/hc_populator.gd")
	Plan.build(1)
	var tp := 0.0
	var tq := 0.0
	var att := 0
	for s in 6:
		var t0 := Time.get_ticks_usec()
		var r = Plan.build(100 + s)
		var t1 := Time.get_ticks_usec()
		Pop.populate(r.layout, world, 100 + s, 4)
		var t2 := Time.get_ticks_usec()
		tp += (t1 - t0) / 1000.0
		tq += (t2 - t1) / 1000.0
	print("plan ", tp / 6.0, " ms  populate ", tq / 6.0, " ms")
	quit()
