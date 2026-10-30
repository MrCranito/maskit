extends EnemySkill
## Frappes au sol différées (eg_glyph.gd), une classe pour plusieurs ids :
##   eg_spike_trap : le Squelette rôdeur actionne un mécanisme ancien — pointes sous le joueur (root) ;
##   eg_arrow_rain : l'Archer sable tire en cloche — pluie de flèches sur la zone du joueur ;
##   eg_sun_flare  : Prêtre du soleil / Pharaon — éruption solaire (aveuglement) ;
##   eg_curse      : Pharaon — malédictions de zone (ralentissement), nombreuses ;
##   eg_venom_spit : Vipère — crachat de venin, flaque qui reste (poison + ralentissement).
## La première frappe vise la position prévue du joueur, les suivantes l'entourent (`spread`).
## Les cercles apparaissent dès le début du télégraphe et frappent `delay` s après la fin de
## l'élan (+ `stagger` s entre deux cercles). Valeurs : [bestiary_egypt] <id>_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const GLYPH := preload("res://scripts/enemies/skills/egypt/eg_glyph.gd")

const BASE := {
	&"eg_spike_trap": {"cooldown": 9.0, "windup": 0.5, "max_range": 420.0, "count": 1, "spread": 70.0,
		"radius": 58.0, "delay": 0.7, "stagger": 0.15, "damage": 10.0, "status": "root", "status_time": 0.7,
		"lead": 0.2, "style": "spikes"},
	&"eg_arrow_rain": {"cooldown": 10.0, "windup": 0.6, "min_range": 160.0, "max_range": 720.0, "count": 3,
		"spread": 90.0, "radius": 62.0, "delay": 0.8, "stagger": 0.18, "damage": 11.0, "lead": 0.4,
		"style": "arrows"},
	&"eg_sun_flare": {"cooldown": 11.0, "windup": 0.7, "max_range": 640.0, "count": 1, "spread": 0.0,
		"radius": 110.0, "delay": 0.9, "stagger": 0.0, "damage": 16.0, "status": "blind", "status_time": 1.4,
		"status_strength": 0.8, "lead": 0.3, "style": "sun"},
	&"eg_curse": {"cooldown": 8.0, "windup": 0.8, "max_range": 760.0, "count": 3, "spread": 150.0,
		"radius": 80.0, "delay": 0.9, "stagger": 0.2, "damage": 16.0, "status": "slow", "status_time": 2.0,
		"status_strength": 0.45, "lead": 0.3, "style": "curse", "need_los": false},
	&"eg_venom_spit": {"cooldown": 9.0, "windup": 0.45, "min_range": 120.0, "max_range": 420.0, "count": 1,
		"spread": 0.0, "radius": 64.0, "delay": 0.55, "stagger": 0.0, "damage": 6.0, "lead": 0.3,
		"linger": 3.5, "linger_dps": 6.0, "linger_slow": 0.35, "style": "venom", "venom": true,
		"venom_dps": 3.0, "venom_time": 3.0, "venom_slow": 0.2, "venom_max_stacks": 3},
}

var spawned: Array[Node2D] = []


func defaults() -> Dictionary:
	var base: Dictionary = BASE.get(id, BASE[&"eg_spike_trap"])
	return Bal.defaults(String(id), base)


func start() -> void:
	e.stop()
	spawned.clear()
	var center := e.predict_player_position(windup() * f("lead"))
	if e.global_position.distance_to(center) > f("max_range"):
		center = e.global_position + (center - e.global_position).normalized() * f("max_range")
	e.face(center - e.global_position)
	e._visual_call(&"play_attack_windup", [windup(), false])
	var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
	var n := maxi(int(f("count")), 1)
	var rot := randf() * TAU
	for i: int in n:
		var pos := center
		if i > 0:
			pos = center + Vector2.from_angle(rot + TAU * float(i - 1) / float(maxi(n - 1, 1))) * f("spread") * randf_range(0.75, 1.1)
		var prm := p.duplicate()
		prm["delay"] = windup() + f("delay") + f("stagger") * float(i)
		prm["damage"] = f("damage") * e.diff_damage_mult * e.phase_damage_mult
		var g := GLYPH.spawn(parent, pos, prm, e)
		if g != null:
			spawned.append(g)


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if t - _dt < windup():
		e._visual_call(&"play_strike", [player_pos() - e.global_position, id == &"eg_arrow_rain"])
		e._play_sfx(&"blade_swing_heavy" if id != &"eg_arrow_rain" else &"enemy_attack")
	return t >= windup() + 0.25
