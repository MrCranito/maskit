extends SceneTree
func _initialize() -> void:
	var P := load("res://scripts/biomes/egypt_pyramids/eg_plan.gd")
	var Pop := load("res://scripts/biomes/egypt_pyramids/eg_populator.gd")
	var world: WorldData = load("res://data/worlds/world_06_egypt_pyramids.tres")
	for s in [1, 7001, 11410, 90003, 90004, 90005]:
		var t := Time.get_ticks_usec()
		var r = P.build(s)
		var t1 := Time.get_ticks_usec()
		Pop.populate(r.layout, world, s, 4)
		var t2 := Time.get_ticks_usec()
		print(s, " plan ", (t1 - t) / 1000.0, " pop ", (t2 - t1) / 1000.0)
	quit()
