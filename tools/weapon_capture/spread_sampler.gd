extends Node
## Échantillonne la dispersion réelle des armes (WeaponLoadout + Player, comme Player.fire) et
## écrit un JSON d'angles d'impact (°) par arme et par situation : premier tir à l'arrêt,
## 10e balle d'une rafale continue, premier tir en courant. Sert aux graphiques avant / après.
##   godot --headless --path . res://tools/weapon_capture/spread_sampler.tscn -- --out=C:/x.json

const WEAPONS := ["pistol_p9", "revolver_peacemaker", "smg_mp5", "smg_vector", "rifle_ak47", "rifle_m4a1",
	"lmg_m249", "sniper_m24", "shotgun_870"]
const N := 300
var _ps: Script = load("res://scripts/player/player.gd")


func _ready() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	await get_tree().process_frame
	seed(12345)
	var new_fire := false
	for m: Dictionary in _ps.get_script_method_list():
		if String(m.get("name", "")) == "pellet_direction":
			new_fire = true
	var res := {"new_fire": new_fire, "weapons": {}}
	for id: String in WEAPONS:
		var w := WeaponCatalog.get_weapon(StringName(id))
		var lo := WeaponLoadout.new(3)
		var list: Array = [w]
		lo.set_weapons(list)
		var d := {"first": [], "burst10": [], "move": [],
			"spread_first": lo.current_inaccuracy(0.0), "spread_move": lo.current_inaccuracy(1.0)}
		for k in N:
			d["first"].append_array(_shot(w, lo.current_inaccuracy(0.0), new_fire))
			d["move"].append_array(_shot(w, lo.current_inaccuracy(1.0), new_fire))
		var s10 := 0.0
		for k2 in N / 3:
			lo.bloom = 0.0
			for b in 9:
				lo.consume_shot()
				lo.tick(w.get_fire_interval())
			s10 = lo.current_inaccuracy(0.0)
			d["burst10"].append_array(_shot(w, s10, new_fire))
			lo.tick(5.0)
		d["spread_burst10"] = s10
		res["weapons"][id] = d
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("ok ", out)
	get_tree().quit()


## Angles (°) des projectiles d'un tir d'imprécision `inacc`, comme Player.fire.
func _shot(w: WeaponData, inacc: float, new_fire: bool) -> Array:
	var out: Array = []
	var count := maxi(w.projectile_count, 1)
	if new_fire:
		var center: Vector2 = Vector2.RIGHT.rotated(_ps.call(&"spread_offset", inacc))
		for i in count:
			out.append(rad_to_deg((_ps.call(&"pellet_direction", center, i, count, w.spread_degrees) as Vector2).angle()))
	else:
		for i in count:
			out.append(rad_to_deg((_ps.call(&"spread_direction", Vector2.RIGHT, i, count, w.spread_degrees, inacc) as Vector2).angle()))
	return out
