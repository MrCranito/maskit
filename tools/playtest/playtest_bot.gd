extends Node
## Bot joueur de playtest (headless) : joue un VRAI raid (scène Raid, Player réel) sans triche.
## Mêmes PV, mêmes armes, mêmes chargeurs qu'un joueur ; il pilote le joueur par deux joysticks
## virtuels (déplacement, visée + tir continu avec l'aide à la visée du mobile), fouille par
## l'action « Fouiller » (maintien immobile, interrompue par un coup), prend le butin comme
## « Tout prendre », se soigne avec les consommables du sac comme l'inventaire, utilise son
## équipement, change d'arme, se met à couvert, va à l'extraction et y canalise.
## Il ne voit que ce que voit le joueur : ennemis non masqués par le brouillard, ligne de vue.
##
## Modes : raid (raid complet), boss (départ à l'entrée de l'arène du boss du monde, avec son
## escorte), duel (une élite seule face au joueur, rue dégagée).
## Profils : prudent (garde ses distances, couvert tôt, extrait tôt), agressif (fonce, descend
## les étages), fouilleur (fouille tout, combat seulement si gêné).
## Sortie : un journal JSON (tools/playtest/README.md) écrit à la fin de la partie.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const MAPS_DIR := "res://data/maps/"
const TIERS := {
	"debutant": {"weapons": [&"pistol_p9", &"smg_mp5"], "gadget": &"gadget_frag"},
	"moyen": {"weapons": [&"rifle_m4a1", &"pistol_glock18", &"sniper_m24"], "gadget": &"gadget_frag"},
	"equipe": {"weapons": [&"rifle_scarh", &"sniper_m82", &"smg_p90"], "gadget": &"gadget_c4"},
}
## Arsenal réaliste par difficulté (raids) : Facile, Normal → débutant ; Difficile, Expert →
## moyen ; Cauchemar → bien équipé.
const TIER_BY_DIFFICULTY := ["debutant", "debutant", "moyen", "moyen", "equipe"]
const PROFILES := {
	"prudent": {"dist": 0.8, "cover_hp": 0.6, "heal_hp": 0.55, "extract_hp": 0.35, "budget": 170.0,
		"floors": false, "loot_radius": 1400.0, "engage": 0.9},
	"agressif": {"dist": 0.42, "cover_hp": 0.25, "heal_hp": 0.4, "extract_hp": 0.15, "budget": 220.0,
		"floors": true, "loot_radius": 900.0, "engage": 1.15},
	"fouilleur": {"dist": 0.65, "cover_hp": 0.45, "heal_hp": 0.5, "extract_hp": 0.3, "budget": 260.0,
		"floors": true, "loot_radius": 99999.0, "engage": 0.8},
}

var mode: String = "raid"
var map_id: String = "perm_dust_creek"
var difficulty: int = 1
var profile_name: String = "prudent"
var tier: String = ""
var seed_value: int = 1
var out_path: String = ""
var enemy_kind: StringName = &""
var max_time: float = 300.0
var smoke: bool = false
## Captures périodiques du viewport (sous xvfb, sans --headless) : dossier et période (s de jeu).
var shots_dir: String = ""
var shot_every: float = 5.0
var _next_shot: float = 1.0

var raid: Raid = null
var player: Player = null
var move_stick: TouchJoystick = null
var aim_stick: TouchJoystick = null
var prof: Dictionary = {}

# --- Mesures ---------------------------------------------------------------------------
var t: float = 0.0
var log: Dictionary = {}
var dmg_taken: Dictionary = {}       ## kind → PV perdus
var hits_taken: Dictionary = {}      ## kind → nombre de coups
var dmg_dealt: Dictionary = {}       ## kind → dégâts infligés
var kills: Dictionary = {}           ## kind → tués
var ttk: Dictionary = {}             ## kind → [s, …] (premier dégât → mort)
var seen_kinds: Dictionary = {}      ## kind → nombre vus (une fois par ennemi)
var elites_met: Dictionary = {}
var boss_info: Dictionary = {}
var items: Dictionary = {}           ## source → rareté → nombre
var item_ids: Dictionary = {}        ## id → nombre
var shots: Dictionary = {}           ## arme → tirs
var gadgets_used: int = 0
var heals_used: int = 0
var containers_opened: int = 0
var corpses_searched: int = 0
var searches_cancelled: int = 0
var last_hit_kind: String = ""
var last_hit_t: float = -1.0
var errors: Array[String] = []
var warnings: Array[String] = []
var worst_frame_ms: float = 0.0
var frame_ms_sum: float = 0.0
var frames: int = 0
var stuck_enemies: Dictionary = {}   ## kind → nombre d'ennemis bloqués
var unreachable_containers: int = 0
var unreachable_kinds: Dictionary = {}
var bot_stuck: int = 0
var floors_visited: Dictionary = {}
var hp_min: float = 9999.0
var bag_value: int = 0
var gold_estimate: int = 0
var outcome: String = ""
var killer: String = ""
var timeline: Array = []
var phase_deaths: int = -1
var death_skill: String = ""
var _first_hit: Dictionary = {}      ## instance id → t du premier dégât
var _enemy_track: Dictionary = {}    ## instance id → {pos, t, kind}
var _known: Dictionary = {}          ## instance id → true (déjà vu)
var _last_frame_us: int = 0
var _logger: Object = null
var _xp0: int = 0
var _done: bool = false

# --- Cerveau ---------------------------------------------------------------------------
var _state: String = "explore"
var _target_enemy: Enemy = null
var _goal: Node2D = null
var _goal_pos: Vector2 = Vector2.INF
var _path: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _repath_left: float = 0.0
var _think_left: float = 0.0
var _stuck_check_left: float = 1.5
var _stuck_pos: Vector2 = Vector2.ZERO
var _stuck_strikes: int = 0
var _bad_goals: Dictionary = {}       ## instance id / clé → true (inaccessible)
var _visited_rooms: Dictionary = {}
var _strafe_sign: float = 1.0
var _strafe_left: float = 0.0
var _switch_cd: float = 0.0
var _gadget_cd: float = 0.0
var _heal_cd: float = 0.0
var _cover_pos: Vector2 = Vector2.INF
var _cover_left: float = 0.0
var _search_target: LootContainer = null
var _search_wait: float = 0.0
var _extracting: bool = false
var _jitter_left: float = 0.0
var _jitter_dir: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters2D.new()


## Fin de partie (mode intégré, tests) : le journal complet.
signal finished(result: Dictionary)

## Mode intégré (tests GUT) : paramètres passés par configure(), raid instancié sous
## `raid_parent` au lieu de changer de scène, pas de quit() à la fin.
var embedded: bool = false
var raid_parent: Node = null


func configure(opts: Dictionary, parent: Node) -> void:
	embedded = true
	raid_parent = parent
	mode = str(opts.get("mode", mode))
	map_id = str(opts.get("map", map_id))
	difficulty = int(opts.get("difficulty", difficulty))
	profile_name = str(opts.get("profile", profile_name))
	tier = str(opts.get("tier", ""))
	seed_value = int(opts.get("seed", seed_value))
	max_time = float(opts.get("max_time", max_time))
	enemy_kind = StringName(str(opts.get("enemy", "")))


func _ready() -> void:
	for a: String in ([] if embedded else OS.get_cmdline_user_args()):
		var kv := a.trim_prefix("--").split("=", true, 1)
		var k := kv[0]
		var v := kv[1] if kv.size() > 1 else ""
		match k:
			"mode": mode = v
			"map": map_id = v
			"difficulty": difficulty = int(v)
			"profile": profile_name = v
			"tier": tier = v
			"seed": seed_value = int(v)
			"out": out_path = v
			"enemy": enemy_kind = StringName(v)
			"max-time": max_time = float(v)
			"smoke": smoke = true
			"shots": shots_dir = v
			"shot-every": shot_every = float(v)
	if tier.is_empty():
		tier = TIER_BY_DIFFICULTY[clampi(difficulty, 0, 4)]
	prof = PROFILES.get(profile_name, PROFILES["prudent"])
	_rng.seed = hash([seed_value, profile_name, mode])
	_ray.collision_mask = 1
	if not embedded:
		Engine.max_fps = 0
		_install_logger()
	process_priority = -10
	# Le jeu se met en pause à la mort (écran de fin) : le bot doit continuer pour clore le journal.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10
	_setup.call_deferred()


# --- Journal des erreurs Godot ----------------------------------------------------------

class BotLogger extends Logger:
	var bot: Node = null

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var msg := "%s:%d %s %s" % [file.get_file(), line, code, rationale]
		if bot != null and is_instance_valid(bot):
			bot.call_deferred(&"_note_error", msg, error_type == ERROR_TYPE_WARNING)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _install_logger() -> void:
	var lg := BotLogger.new()
	lg.bot = self
	OS.add_logger(lg)
	_logger = lg


func _note_error(msg: String, warning: bool) -> void:
	var list := warnings if warning else errors
	if list.size() < 60 and not list.has(msg):
		list.append(msg)


# --- Préparation -----------------------------------------------------------------------

func _setup() -> void:
	PlaytestProbe.enabled = true
	PlaytestProbe.sink = self
	Profile.from_dict({})
	_xp0 = Profile.raider_xp
	var card_path := MAPS_DIR + map_id + ".tres"
	var card: Resource = load(card_path) if ResourceLoader.exists(card_path) else null
	if card == null:
		_abort("carte introuvable : " + card_path)
		return
	GameState.set_current_map(card, false)
	GameState.difficulty = clampi(difficulty, 0, 4)
	GameState.run_seed = seed_value
	GameState.raid_inventory = Inventory.from_balance()
	var list: Array[WeaponData] = []
	for id: StringName in TIERS[tier]["weapons"]:
		var w := WeaponCatalog.get_weapon(id)
		if w != null:
			list.append(w)
	GameState.raid_weapons = list
	GameState.raid_gadget = WeaponCatalog.get_weapon(TIERS[tier]["gadget"])
	Profile.raid_gadget = GameState.raid_gadget
	Profile.raid_in_progress = true
	log = {"mode": mode, "map": map_id, "difficulty": difficulty, "profile": profile_name, "tier": tier,
		"seed": seed_value, "world": String(card.get("world_path")).get_file().get_basename(),
		"arsenal": TIERS[tier]["weapons"].map(func(x: StringName) -> String: return String(x)),
		"gadget": String(TIERS[tier]["gadget"])}
	if embedded:
		raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
		raid_parent.add_child(raid)
		await _wait_for(func() -> bool: return is_instance_valid(raid.player), 20.0)
	else:
		get_tree().change_scene_to_file(RAID_SCENE)
		await _wait_for(func() -> bool: return get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player), 20.0)
		raid = get_tree().current_scene as Raid
	if raid == null:
		_abort("raid non chargé")
		return
	player = raid.player as Player
	move_stick = TouchJoystick.new()
	aim_stick = TouchJoystick.new()
	aim_stick.side = &"right"
	player.set_joysticks(move_stick, aim_stick)
	player.fired.connect(_on_fired)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.boss_phase_changed.connect(_on_boss_phase)
	EventBus.boss_engaged.connect(func(b: Node2D) -> void: _boss_seen(b))
	EventBus.item_picked_up.connect(_on_picked)
	EventBus.floor_changed.connect(func(f: int) -> void:
		floors_visited[str(f)] = true
		_on_floor_ready.call_deferred())
	floors_visited[str(raid.current_floor)] = true
	match mode:
		"boss":
			_setup_boss()
		"duel":
			await _setup_duel()
	_on_floor_ready()
	_last_frame_us = Time.get_ticks_usec()
	_playing = true


func _wait_for(cond: Callable, max_s: float) -> bool:
	var until := Time.get_ticks_msec() + int(max_s * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() > until:
			return false
		await get_tree().process_frame
	return true


func _abort(msg: String) -> void:
	errors.append("BOT: " + msg)
	outcome = "erreur"
	_finish()


## Mode boss : étage du boss, joueur posé à l'entrée de l'arène (côté extérieur de sa porte).
func _setup_boss() -> void:
	var wd := raid.world as WorldData
	var boss_kind: StringName = wd.boss_kind if wd != null else &""
	log["boss_kind"] = String(boss_kind)
	for fi: Variant in raid.floors:
		var l: FloorLayout = raid.floors[fi]
		for sp: FloorLayout.Spawn in l.enemy_spawns:
			if sp.kind != boss_kind:
				continue
			var room := l.get_room(sp.room_id) if sp.room_id >= 0 else l.room_at(sp.cell)
			var cell := _arena_entry(l, room, sp.cell)
			if int(fi) != raid.current_floor:
				raid.go_to_floor(int(fi), cell)
			else:
				raid.place_player(cell)
			log["boss_floor"] = int(fi)
			return
	_abort("pas de boss dans ce raid")


func _arena_entry(l: FloorLayout, room: FloorLayout.Room, boss_cell: Vector2i) -> Vector2i:
	if room == null:
		return boss_cell + Vector2i(8, 0)
	for d: FloorLayout.Door in l.doors:
		if d.room_a != room.id and d.room_b != room.id:
			continue
		for off: Vector2i in [Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]:
			var c := d.cell + off
			if not room.rect.has_point(c) and FloorLayout.is_walkable_tile(l.get_tile(c)):
				return c
	# Arène ouverte : bord de la salle, côté opposé au boss.
	var center := room.rect.get_center()
	var dir := Vector2(center - boss_cell).normalized()
	var c2 := center + Vector2i(roundi(dir.x * room.rect.size.x * 0.45), roundi(dir.y * room.rect.size.y * 0.45))
	return c2


## Mode duel : étage vidé (ennemis et tourelles), une élite posée à 7 cases dans une zone dégagée.
func _setup_duel() -> void:
	for e: Node in raid.enemies_container.get_children():
		e.queue_free()
	for tu: Node2D in raid.get_alive_turrets():
		tu.queue_free()
	await get_tree().process_frame
	var l := raid.layout
	var best := Vector2i.ZERO
	var found := false
	var start := raid.get_player_cell()
	for r in range(6, 12):
		for k in 16:
			var a := TAU * k / 16.0
			var c := start + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			if not FloorLayout.is_walkable_tile(l.get_tile(c)):
				continue
			if _los(FloorLayout.cell_to_world(start), FloorLayout.cell_to_world(c)):
				best = c
				found = true
				break
		if found:
			break
	if not found:
		_abort("pas de position de duel dégagée")
		return
	var data := Raid.load_enemy_data(enemy_kind)
	if data == null:
		_abort("élite inconnue " + String(enemy_kind))
		return
	var e2 := raid._add_enemy(data, FloorLayout.cell_to_world(best), "Duel")
	log["enemy"] = String(enemy_kind)
	if e2 is Enemy:
		(e2 as Enemy).awareness = 1.0


func _on_floor_ready() -> void:
	_path = PackedVector2Array()
	_goal = null
	_target_enemy = null
	_search_target = null
	for e: Node in raid.enemies_container.get_children():
		_watch_enemy(e)
	if mode == "raid":
		_check_reachability()


func _watch_enemy(e: Node) -> void:
	var en := e as Enemy
	if en == null or en.has_meta(&"pt_watched"):
		return
	en.set_meta(&"pt_watched", true)
	var id := en.get_instance_id()
	var kind := String(en.data.kind) if en.data != null else "?"
	en.damaged.connect(func(amount: float, _hp: float) -> void:
		dmg_dealt[kind] = float(dmg_dealt.get(kind, 0.0)) + amount
		if not _first_hit.has(id):
			_first_hit[id] = t)
	if en.has_signal(&"phase_changed") and en.data != null and en.data.boss:
		en.phase_changed.connect(func(p: int) -> void:
			boss_info["max_phase"] = maxi(int(boss_info.get("max_phase", 1)), p))


## Conteneurs de l'étage sans chemin depuis le joueur (comptés une fois par étage).
func _check_reachability() -> void:
	if floors_visited.has("chk_" + str(raid.current_floor)):
		return
	floors_visited["chk_" + str(raid.current_floor)] = true
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(player) or _done:
		return
	var from := player.global_position
	for c: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		var lc := c as LootContainer
		if lc == null or lc is EnemyCorpse:
			continue
		var p := _nav_path(from, lc.global_position)
		var reach := 120.0 + lc.get_interact_reach()
		if p.is_empty() or p[p.size() - 1].distance_to(lc.global_position) > reach:
			unreachable_containers += 1
			unreachable_kinds[String(lc.kind)] = int(unreachable_kinds.get(String(lc.kind), 0)) + 1


# --- Sondes -----------------------------------------------------------------------------

func on_player_hit(amount: float, source: Node) -> void:
	var kind := _source_kind(source)
	dmg_taken[kind] = float(dmg_taken.get(kind, 0.0)) + amount
	hits_taken[kind] = int(hits_taken.get(kind, 0)) + 1
	last_hit_kind = kind
	last_hit_t = t
	var boss := _boss_node()
	if boss != null and is_instance_valid(boss):
		boss_info["hp_ratio_at_last_hit"] = boss.hp / maxf(boss.max_hp, 1.0)
		var sk := _skill_name(source)
		if not sk.is_empty():
			death_skill = sk


static func _source_kind(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return "inconnu"
	var n: Node = source
	for i in 4:
		if n is Enemy:
			return String((n as Enemy).data.kind)
		for prop: StringName in [&"shooter", &"owner_enemy", &"source", &"enemy", &"caster", &"owner_node"]:
			var v: Variant = n.get(prop)
			if is_instance_valid(v) and v is Enemy:
				return String((v as Enemy).data.kind)
		if n.get_script() != null and String(n.get_script().resource_path).contains("turret"):
			return "tourelle"
		if n.get_parent() == null:
			break
		n = n.get_parent()
	var sc: Script = source.get_script()
	return sc.resource_path.get_file().get_basename() if sc != null else source.get_class()


func _skill_name(source: Node) -> String:
	if source is Enemy:
		var e := source as Enemy
		return String(e.active_skill.id) if e.active_skill != null and e.active_skill.get(&"id") != null else "attaque"
	var sc: Script = source.get_script() if source != null and is_instance_valid(source) else null
	return sc.resource_path.get_file().get_basename() if sc != null else ""


func _on_fired(_dir: Vector2) -> void:
	var w := player.weapon
	var k := String(w.id) if w != null else "?"
	shots[k] = int(shots.get(k, 0)) + 1


func _on_enemy_died(enemy: Node2D, _pos: Vector2) -> void:
	var en := enemy as Enemy
	if en == null or en.data == null:
		return
	var kind := String(en.data.kind)
	kills[kind] = int(kills.get(kind, 0)) + 1
	var id := en.get_instance_id()
	if _first_hit.has(id):
		if not ttk.has(kind):
			ttk[kind] = []
		(ttk[kind] as Array).append(snappedf(t - float(_first_hit[id]), 0.01))
	if en.data.boss:
		boss_info["killed"] = true
		boss_info["kill_t"] = snappedf(t, 0.1)
	if en.data.elite:
		var em: Dictionary = elites_met.get(kind, {"met": 0, "killed": 0})
		em["killed"] = int(em["killed"]) + 1
		elites_met[kind] = em


func _on_boss_phase(_boss: Node2D, phase_index: int, phase_name: String) -> void:
	if not shots_dir.is_empty():
		_shot_later("boss_phase%d" % (phase_index + 1), 0.6)
	boss_info["max_phase"] = maxi(int(boss_info.get("max_phase", 1)), phase_index + 1)
	(boss_info.get_or_add("phases", []) as Array).append({"t": snappedf(t, 0.1), "phase": phase_index + 1, "name": phase_name})


func _boss_seen(b: Node2D) -> void:
	var e := b as Enemy
	if e == null or boss_info.has("kind"):
		return
	boss_info["kind"] = String(e.data.kind)
	boss_info["met_t"] = snappedf(t, 0.1)


func _boss_node() -> Enemy:
	for e: Node2D in raid.get_alive_enemies():
		var en := e as Enemy
		if en != null and en.data != null and en.data.boss:
			return en
	return null


func _on_picked(item: Resource, count: int) -> void:
	var it := item as ItemData
	if it == null or _taking:
		return
	_count_item("sol", it, count)


func _count_item(source: String, it: ItemData, count: int) -> void:
	# Par source et rareté : nombre d'objets (une pile = 1, comme LootRoller) ; quantités à part.
	var by: Dictionary = items.get_or_add(source, {})
	var r := str(it.rarity)
	by[r] = int(by.get(r, 0)) + 1
	item_ids[String(it.id)] = int(item_ids.get(String(it.id), 0)) + count


# --- Boucle -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if raid == null or _done or not _playing:
		return
	# Garde-fous : joueur remplacé (changement d'étage) ou perdu, partie trop longue en temps réel.
	if not is_instance_valid(player):
		if is_instance_valid(raid.player):
			player = raid.player as Player
			player.set_joysticks(move_stick, aim_stick)
			if not player.fired.is_connected(_on_fired):
				player.fired.connect(_on_fired)
		else:
			_lost_player += delta
			if _lost_player > 5.0:
				_abort("joueur introuvable (raid t=%.1f s)" % t)
			return
	if Time.get_ticks_msec() - _start_ms > int(real_limit * 1000.0):
		errors.append("BOT: limite de temps réel atteinte (t=%.1f s)" % t)
		outcome = "temps"
		_finish()
		return
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		var ms := float(now - _last_frame_us) / 1000.0
		frames += 1
		frame_ms_sum += ms
		if t > 2.0:
			worst_frame_ms = maxf(worst_frame_ms, ms)
	_last_frame_us = now
	t += delta
	if _trace and int(t / 10.0) != int((t - delta) / 10.0):
		print("TRACE reel=%d t=%.0f etat=%s etage=%d pv=%.0f pos=%s ms=%.1f ennemis=%d" % [Time.get_ticks_msec(), t, _state, raid.current_floor, player.hp, player.global_position, frame_ms_sum / maxf(frames, 1), raid.get_alive_enemies().size()])
	hp_min = minf(hp_min, player.hp)
	if not shots_dir.is_empty() and t >= _next_shot:
		_next_shot += shot_every
		_shot("t%04d" % int(t))
	if raid.is_raid_over():
		_end_from_raid()
		return
	if not player.is_alive():
		# Mort : on attend l'écran de fin (XP et bilan comptés par le jeu), 5 s au plus.
		_sticks(Vector2.ZERO, Vector2.ZERO)
		if _dead_wait == 0.0:
			_death_t = t
		_dead_wait += delta
		if _dead_wait > 5.0:
			_end_from_raid()
		return
	if t > max_time:
		outcome = "temps"
		_finish()
		return
	if raid.is_transitioning():
		_sticks(Vector2.ZERO, Vector2.ZERO)
		return
	_switch_cd -= delta
	_gadget_cd -= delta
	_heal_cd -= delta
	_cover_left -= delta
	_strafe_left -= delta
	_think_left -= delta
	_repath_left -= delta
	_jitter_left -= delta
	if _think_left <= 0.0:
		_think_left = 0.1
		_think()
		_track_enemies()
	_act(delta)


func _shot_later(tag: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not _done:
		_shot(tag)


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
		img.save_png(shots_dir.path_join("%s_%s.png" % [tag, _state]))


func _sticks(move: Vector2, aim: Vector2) -> void:
	move_stick.output = move.limit_length(1.0)
	aim_stick.output = aim


## Décision (10 fois par seconde).
func _think() -> void:
	_bag_snapshot()
	_maybe_heal()
	var enemy := _pick_enemy()
	if enemy != _target_enemy:
		_target_enemy = enemy
	if _search_target != null and _target_enemy == null:
		return
	if _target_enemy != null:
		_state = "fight"
		_cancel_search()
		return
	if _extracting:
		_state = "extract"
		return
	if mode == "raid" and _should_extract():
		_extracting = true
		_state = "extract"
		_goal = null
		_path = PackedVector2Array()
		return
	if mode != "raid":
		_state = "hunt"
		return
	_state = "explore"


func _should_extract() -> bool:
	if t > float(prof["budget"]):
		return true
	if player.hp / player.max_hp < float(prof["extract_hp"]) and _heal_items() == 0:
		return true
	var inv := GameState.raid_inventory
	if inv != null and inv.used_slots() >= inv.capacity() - 1:
		return true
	return false


## Ennemi visible le plus menaçant (le joueur ne voit que ce que montre le brouillard).
func _pick_enemy() -> Enemy:
	var best: Enemy = null
	var best_score := INF
	var w := player.weapon
	var rng_max := (w.range if w != null else 500.0) * float(prof["engage"])
	var me := player.global_position
	for n: Node2D in raid.get_alive_enemies():
		var e := n as Enemy
		if e == null or not e.is_visible_in_tree():
			continue
		var d := me.distance_to(e.global_position)
		var close := d < 260.0
		if d > rng_max and not close:
			continue
		if not _los(me, e.global_position):
			continue
		var score := d
		if e.data.boss:
			score *= 1.4 if mode != "boss" else 0.7
		if e.can_see_player:
			score *= 0.7
		if score < best_score:
			best_score = score
			best = e
	return best


func _track_enemies() -> void:
	for n: Node2D in raid.get_alive_enemies():
		var e := n as Enemy
		if e == null:
			continue
		var id := e.get_instance_id()
		if not _known.has(id) and e.is_visible_in_tree():
			_known[id] = true
			var kind := String(e.data.kind)
			seen_kinds[kind] = int(seen_kinds.get(kind, 0)) + 1
			if e.data.elite:
				var em: Dictionary = elites_met.get(kind, {"met": 0, "killed": 0})
				em["met"] = int(em["met"]) + 1
				elites_met[kind] = em
			if e.data.boss:
				_boss_seen(e)
			_watch_enemy(e)
		# Ennemi bloqué : alerté, veut bouger, n'avance pas pendant 5 s.
		var tr: Dictionary = _enemy_track.get(id, {})
		var moving_wanted := e.awareness >= 1.0 and e.desired_velocity.length() > 20.0
		if tr.is_empty() or not moving_wanted:
			_enemy_track[id] = {"pos": e.global_position, "t": t}
			continue
		if e.global_position.distance_to(tr["pos"]) > 24.0:
			_enemy_track[id] = {"pos": e.global_position, "t": t}
		elif t - float(tr["t"]) > 5.0 and not tr.get("flag", false):
			tr["flag"] = true
			var kind2 := String(e.data.kind)
			stuck_enemies[kind2] = int(stuck_enemies.get(kind2, 0)) + 1


## Action (chaque image).
func _act(delta: float) -> void:
	match _state:
		"fight":
			_fight(delta)
		"extract":
			_extract(delta)
		"hunt":
			_hunt(delta)
		_:
			_explore(delta)


# --- Combat -----------------------------------------------------------------------------

func _fight(_delta: float) -> void:
	var e := _target_enemy
	if e == null or not is_instance_valid(e) or not e.is_alive():
		_target_enemy = null
		_sticks(Vector2.ZERO, Vector2.ZERO)
		return
	var me := player.global_position
	var to := e.global_position - me
	var d := to.length()
	_choose_weapon(d)
	_maybe_gadget(e, d)
	var aim := to.normalized()
	# Petite avance sur la cible en mouvement (comme un joueur).
	if e.velocity.length() > 30.0:
		var w := player.weapon
		var lead := d / maxf(w.projectile_speed if w != null else 700.0, 200.0)
		aim = (e.global_position + e.velocity * lead * 0.5 - me).normalized()
	var hp_ratio := player.hp / player.max_hp
	# Esquive : un ennemi proche est en train d'armer une attaque (télégraphe visible).
	if _dodge_left > 0.0:
		_dodge_left -= get_physics_process_delta_time()
		_sticks(_avoid_walls(_dodge_dir), aim)
		return
	var tele := _telegraphing_enemy()
	if tele != null:
		var away := (me - tele.global_position).normalized()
		_dodge_dir = away.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
		if tele.data.is_ranged():
			_dodge_dir = _dodge_dir  # tir : pas de côté
		else:
			_dodge_dir = (_dodge_dir + away).normalized()  # mêlée : en arrière et de côté
		_dodge_left = 0.35
		dodges += 1
		if not shots_dir.is_empty() and not _tele_shot.has(tele.data.kind):
			_tele_shot[tele.data.kind] = true
			_shot("telegraphe_" + String(tele.data.kind))
		_sticks(_avoid_walls(_dodge_dir), aim)
		return
	# Débordé (3 ennemis alertés ou plus tout près) : repli, sauf l'agressif.
	if profile_name != "agressif":
		var crowd := Vector2.ZERO
		var nc := 0
		for n: Node2D in raid.get_alive_enemies():
			var en := n as Enemy
			if en != null and en.awareness >= 1.0 and me.distance_to(en.global_position) < 380.0:
				crowd += en.global_position
				nc += 1
		if nc >= 3:
			_sticks(_steer_away(crowd / nc), aim)
			return
	var want_cover := hp_ratio < float(prof["cover_hp"]) or (player.is_reloading() and profile_name != "agressif")
	var move := Vector2.ZERO
	if want_cover:
		if _cover_left <= 0.0 or _cover_pos == Vector2.INF:
			_cover_pos = _find_cover(e.global_position)
			_cover_left = 2.0
		if _cover_pos != Vector2.INF:
			move = _steer_to(_cover_pos)
	# Mêlée qui fonce : on recule en tirant (kiting), sauf le profil agressif à bout portant.
	if move == Vector2.ZERO:
		var rusher := _nearest_melee(170.0 if profile_name == "agressif" else 230.0)
		if rusher != null:
			move = _steer_away(rusher.global_position)
	if move == Vector2.ZERO:
		var w2 := player.weapon
		var ideal := (w2.range if w2 != null else 500.0) * float(prof["dist"])
		if d > ideal * 1.15:
			move = _steer_to(e.global_position)
		elif d < ideal * 0.7:
			move = _steer_away(e.global_position)
		else:
			if _strafe_left <= 0.0:
				_strafe_left = _rng.randf_range(0.8, 1.8)
				_strafe_sign = -_strafe_sign
			move = aim.orthogonal() * _strafe_sign * 0.8
			move = _avoid_walls(move)
	_sticks(move, aim)


## Ennemi proche dans la phase d'armement de son attaque (le joueur voit le télégraphe).
func _telegraphing_enemy() -> Enemy:
	for n: Node2D in raid.get_alive_enemies():
		var e := n as Enemy
		if e == null or not e.is_visible_in_tree() or e.state_machine == null:
			continue
		var st: Node = e.state_machine.current_state
		if st == null or st.get(&"_step") != 0 or not String(st.get_script().resource_path).ends_with("enemy_attack_state.gd"):
			continue
		var reach := e.data.attack_range * 1.25 + 40.0
		if player.global_position.distance_to(e.global_position) <= reach:
			return e
	return null


func _nearest_melee(radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for n: Node2D in raid.get_alive_enemies():
		var e := n as Enemy
		if e == null or e.data.is_ranged() or not e.is_visible_in_tree():
			continue
		var d := player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _choose_weapon(d: float) -> void:
	if _switch_cd > 0.0:
		return
	var ws := player.get_weapons()
	if ws.size() < 2:
		return
	var cur := player.current_slot
	var best := cur
	var best_s := -INF
	for i in ws.size():
		var w := ws[i]
		if w == null:
			continue
		var s := 0.0
		s += 2.0 if d <= w.range * 0.9 else -2.0
		s += w.damage * w.fire_rate * float(maxi(w.projectile_count, 1)) / 30.0
		if w.category == &"sniper" and d < 250.0:
			s -= 3.0
		if w.category == &"smg" and d > 420.0:
			s -= 1.5
		if i == cur and player.is_reloading():
			s -= 4.0
		if i == cur:
			s += 0.5
		if s > best_s:
			best_s = s
			best = i
	if best != cur:
		player.switch_to(best)
		_switch_cd = 1.2


func _maybe_gadget(e: Enemy, d: float) -> void:
	if _gadget_cd > 0.0 or player.get_gadget() == null or player.get_gadget_charges() <= 0:
		return
	var g := player.get_gadget()
	if d > g.throw_range * 1.05 or d < 110.0:
		return
	var crowd := 0
	for n: Node2D in raid.get_alive_enemies():
		if n.global_position.distance_to(e.global_position) < 180.0:
			crowd += 1
	if crowd >= 2 or e.data.elite or e.data.boss:
		if player.use_gadget((e.global_position - player.global_position).normalized()):
			gadgets_used += 1
			_gadget_cd = 4.0


func _heal_items() -> int:
	var inv := GameState.raid_inventory
	var n := 0
	if inv == null:
		return 0
	for i in inv.capacity():
		var sl := inv.get_slot(i)
		if not sl.is_empty() and (sl["item"] as ItemData).is_usable():
			n += int(sl.get("count", 1))
	return n


## Soin comme depuis l'inventaire : consomme l'objet de soin le plus adapté.
func _maybe_heal() -> void:
	if _heal_cd > 0.0 or player.hp >= player.max_hp * float(prof["heal_hp"]):
		return
	var inv := GameState.raid_inventory
	if inv == null:
		return
	var best: ItemData = null
	for i in inv.capacity():
		var sl := inv.get_slot(i)
		if sl.is_empty():
			continue
		var it := sl["item"] as ItemData
		if it.is_usable() and (best == null or absf(it.heal_amount - (player.max_hp - player.hp)) < absf(best.heal_amount - (player.max_hp - player.hp))):
			best = it
	if best == null:
		return
	inv.remove_item(best.id, 1)
	player.heal(best.heal_amount)
	heals_used += 1
	_heal_cd = 2.5


func _find_cover(threat: Vector2) -> Vector2:
	var me := player.global_position
	var best := Vector2.INF
	var best_d := INF
	for r: float in [110.0, 170.0, 240.0]:
		for k in 12:
			var p := me + Vector2.from_angle(TAU * k / 12.0) * r
			if _los(threat, p) or not _los(me, p):
				continue
			var dd := p.distance_to(me) + (300.0 if p.distance_to(threat) < me.distance_to(threat) else 0.0)
			if dd < best_d:
				best_d = dd
				best = p
		if best != Vector2.INF:
			break
	return best


func _los(a: Vector2, b: Vector2) -> bool:
	_ray.from = a
	_ray.to = b
	return player.get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


# --- Exploration, fouille ----------------------------------------------------------------

func _explore(delta: float) -> void:
	if _search_target != null:
		_do_search(delta)
		return
	if _goal == null or not is_instance_valid(_goal) or _goal_done(_goal):
		_goal = _next_goal()
		_path = PackedVector2Array()
		if _goal == null:
			_goal_pos = _next_room_goal()
			if _goal_pos == Vector2.INF:
				if bool(prof["floors"]) and _try_stairs():
					return
				_extracting = true
				return
	var target := _goal.global_position if _goal != null and is_instance_valid(_goal) else _goal_pos
	if _goal != null and is_instance_valid(_goal) and _goal is LootContainer:
		var lc := _goal as LootContainer
		if player.global_position.distance_to(lc.global_position) < 52.0 + lc.get_interact_reach():
			_sticks(Vector2.ZERO, Vector2.ZERO)
			_start_search(lc)
			return
	elif _goal == null and player.global_position.distance_to(target) < 60.0:
		_visited_rooms[_room_key(target)] = true
		_goal_pos = Vector2.INF
		return
	_sticks(_steer_to(target), Vector2.ZERO)


func _goal_done(g: Node2D) -> bool:
	if g is LootContainer:
		return not (g as LootContainer).can_interact() or (g as LootContainer).is_emptied() \
			or _bad_goals.has(g.get_instance_id())
	if g is GroundLoot:
		return (g as GroundLoot).count <= 0
	return false


func _next_goal() -> Node2D:
	var me := player.global_position
	var best: Node2D = null
	var best_d := INF
	var radius := float(prof["loot_radius"])
	var inv := GameState.raid_inventory
	if inv != null and inv.used_slots() >= inv.capacity() - 1:
		return null
	for c: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		var lc := c as LootContainer
		if lc == null or not lc.is_inside_tree() or _goal_done(lc):
			continue
		if lc.state == LootContainer.State.OPENED and lc.entries.is_empty():
			continue
		var d := me.distance_to(lc.global_position)
		if d > radius:
			continue
		if lc is EnemyCorpse:
			d *= 0.6
		if d < best_d:
			best_d = d
			best = lc
	for g: Node in get_tree().get_nodes_in_group(GroundLoot.GROUP):
		var gl := g as GroundLoot
		if gl == null or _bad_goals.has(gl.get_instance_id()):
			continue
		var d2 := me.distance_to(gl.global_position) * 0.5
		if d2 < best_d:
			best_d = d2
			best = gl
	return best


func _room_key(p: Vector2) -> String:
	var room := raid.layout.room_at(FloorLayout.world_to_cell(p))
	return "%d:%d" % [raid.current_floor, room.id if room != null else -1]


## Centre de la salle non visitée la plus proche (agressif : salles de combat d'abord).
func _next_room_goal() -> Vector2:
	var me := player.global_position
	var best := Vector2.INF
	var best_d := INF
	for room: FloorLayout.Room in raid.layout.rooms:
		var key := "%d:%d" % [raid.current_floor, room.id]
		if _visited_rooms.has(key) or _bad_goals.has(key):
			continue
		var c := FloorLayout.cell_to_world(room.rect.get_center())
		var d := me.distance_to(c)
		if profile_name == "agressif" and (room.type == &"combat" or room.type == &"boss"):
			d *= 0.5
		if profile_name == "prudent" and room.type == &"boss":
			continue
		if d < best_d:
			best_d = d
			best = c
	if best != Vector2.INF and _room_count_visited() > 14 and profile_name == "prudent":
		return Vector2.INF
	return best


func _room_count_visited() -> int:
	var n := 0
	for k: String in _visited_rooms:
		if k.begins_with(str(raid.current_floor) + ":"):
			n += 1
	return n


func _start_search(lc: LootContainer) -> void:
	_search_target = lc
	_search_wait = 0.0
	if lc.state == LootContainer.State.CLOSED:
		lc.interact(player)


func _cancel_search() -> void:
	if _search_target != null and is_instance_valid(_search_target):
		if _search_target.is_searching():
			_search_target.release_interact(player)
			searches_cancelled += 1
	_search_target = null


func _do_search(delta: float) -> void:
	var lc := _search_target
	_sticks(Vector2.ZERO, Vector2.ZERO)
	if lc == null or not is_instance_valid(lc):
		_search_target = null
		return
	_search_wait += delta
	if lc.state == LootContainer.State.CLOSED:
		if _search_wait > 0.4:
			lc.interact(player)  # fouille annulée (coup reçu) : on recommence
			_search_wait = 0.0
		return
	if lc.state == LootContainer.State.SEARCHING:
		if _search_wait > 12.0:
			_bad_goals[lc.get_instance_id()] = true
			_cancel_search()
		return
	# Ouvert : « Tout prendre ».
	var inv := GameState.raid_inventory
	var src := "cadavre" if lc is EnemyCorpse else String(lc.kind)
	var before := {}
	for e: Dictionary in lc.entries:
		before[(e["item"] as ItemData).id] = int(e["count"])
	var was_closed := not lc.has_meta(&"pt_opened")
	_taking = true
	lc.take_all(inv)
	_taking = false
	var after := {}
	for e2: Dictionary in lc.entries:
		after[(e2["item"] as ItemData).id] = int(e2["count"])
	for id: StringName in before:
		var got := int(before[id]) - int(after.get(id, 0))
		if got > 0:
			_count_item(src if src == "cadavre" else ("tresor" if lc.room_type == &"super_loot" else "conteneur"), LootDB.get_item(id), got)
	if was_closed:
		lc.set_meta(&"pt_opened", true)
		if lc is EnemyCorpse:
			corpses_searched += 1
		else:
			containers_opened += 1
	if not lc.is_emptied():
		_bad_goals[lc.get_instance_id()] = true  # sac plein pour ce contenu
	_search_target = null
	_goal = null


func _bag_snapshot() -> void:
	var inv := GameState.raid_inventory
	if inv != null:
		bag_value = inv.total_value()
		gold_estimate = Economy.estimate_inventory(inv)


func _try_stairs() -> bool:
	var l := raid.layout
	for s: FloorLayout.Stairs in l.stairs:
		if floors_visited.has(str(s.target_floor)) or not raid.has_floor(s.target_floor):
			continue
		var key := "stairs:%d:%d" % [raid.current_floor, s.target_floor]
		if _bad_goals.has(key):
			continue
		_goal = null
		_goal_pos = FloorLayout.cell_to_world(s.cell)
		_visited_rooms["dummy"] = true
		_stairs_goal = key
		return true
	return false


var _stairs_goal: String = ""
var _taking: bool = false
var _playing: bool = false
var _dodge_left: float = 0.0
var _dodge_dir: Vector2 = Vector2.ZERO
var dodges: int = 0
var _lost_player: float = 0.0
var _dead_wait: float = 0.0
var _lost_boss: float = 0.0
var _death_t: float = -1.0
var _tele_shot: Dictionary = {}
var _trace: bool = OS.get_environment("PLAYTEST_TRACE") == "1"
var _start_ms: int = Time.get_ticks_msec()
## Durée réelle maximale d'une partie (s) : au-delà, fin « temps » notée en erreur.
var real_limit: float = 480.0


# --- Extraction -------------------------------------------------------------------------

func _extract(_delta: float) -> void:
	var l := raid.layout
	if l.extraction_cells.is_empty():
		# Pas d'extraction à cet étage : retour vers le rez-de-chaussée.
		for s: FloorLayout.Stairs in l.stairs:
			if absi(s.target_floor) < absi(raid.current_floor):
				_sticks(_steer_to(FloorLayout.cell_to_world(s.cell)), Vector2.ZERO)
				return
		outcome = "bloque"
		_finish()
		return
	var me := player.global_position
	var best := Vector2.INF
	var best_d := INF
	for c: Vector2i in l.extraction_cells:
		var p := FloorLayout.cell_to_world(c)
		var d := me.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	if raid.layout.extraction_cells.has(raid.get_player_cell()):
		# Canalisation : on reste, on tire sur ce qui approche.
		var e := _pick_enemy()
		_sticks(Vector2.ZERO, (e.global_position - me).normalized() if e != null else Vector2.ZERO)
		return
	_sticks(_steer_to(best), Vector2.ZERO)


## Mode boss / duel : chercher l'ennemi (le plus proche vivant), puis combat.
func _hunt(_delta: float) -> void:
	var target: Node2D = null
	var best_d := INF
	for n: Node2D in raid.get_alive_enemies():
		var e := n as Enemy
		if e == null:
			continue
		if mode == "boss" and not (e.data.boss or e.data.elite):
			continue
		var d := player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			target = e
	if target == null:
		# Victoire seulement sur une mort constatée (duel : l'élite ; boss : le boss). Un boss
		# introuvable sans mort (illusion, disparition) n'est pas une victoire.
		if mode == "duel" or bool(boss_info.get("killed", false)):
			outcome = "victoire"
			_finish()
		elif _boss_node() == null:
			_lost_boss += get_physics_process_delta_time()
			if _lost_boss > 8.0:
				errors.append("BOT: boss introuvable sans mort constatée (t=%.1f s)" % t)
				outcome = "invalide"
				_finish()
		return
	_sticks(_steer_to(target.global_position), Vector2.ZERO)


# --- Navigation -------------------------------------------------------------------------

func _nav_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var map := player.get_world_2d().navigation_map
	return NavigationServer2D.map_get_path(map, a, b, true)


func _steer_to(target: Vector2) -> Vector2:
	var me := player.global_position
	if _jitter_left > 0.0:
		return _jitter_dir
	if _path.is_empty() or _repath_left <= 0.0 or _path[_path.size() - 1].distance_to(target) > 48.0:
		_path = _nav_path(me, target)
		_path_i = 0
		_repath_left = 0.8
		if _path.is_empty() or _path[_path.size() - 1].distance_to(target) > 120.0:
			_mark_unreachable(target)
	while _path_i < _path.size() and me.distance_to(_path[_path_i]) < 18.0:
		_path_i += 1
	var dir := Vector2.ZERO
	if _path_i < _path.size():
		dir = (_path[_path_i] - me).normalized()
	elif me.distance_to(target) > 10.0:
		dir = (target - me).normalized()
	_check_stuck(dir)
	return dir


func _mark_unreachable(target: Vector2) -> void:
	if _goal != null and is_instance_valid(_goal):
		_bad_goals[_goal.get_instance_id()] = true
		_goal = null
	elif _goal_pos != Vector2.INF and _goal_pos.distance_to(target) < 2.0:
		_bad_goals[_room_key(target)] = true
		_goal_pos = Vector2.INF
	if not _stairs_goal.is_empty():
		_bad_goals[_stairs_goal] = true
		_stairs_goal = ""


func _check_stuck(dir: Vector2) -> void:
	_stuck_check_left -= get_physics_process_delta_time()
	if _stuck_check_left > 0.0:
		return
	_stuck_check_left = 1.5
	var me := player.global_position
	if dir != Vector2.ZERO and me.distance_to(_stuck_pos) < 10.0 and _search_target == null:
		_stuck_strikes += 1
		_jitter_dir = Vector2.from_angle(_rng.randf() * TAU)
		_jitter_left = 0.4
		_path = PackedVector2Array()
		if _stuck_strikes >= 4:
			bot_stuck += 1
			_stuck_strikes = 0
			_mark_unreachable(_goal.global_position if _goal != null and is_instance_valid(_goal) else _goal_pos)
	else:
		_stuck_strikes = 0
	_stuck_pos = me


func _steer_away(threat: Vector2) -> Vector2:
	var me := player.global_position
	var away := (me - threat).normalized()
	for k in [0, 1, -1, 2, -2]:
		var dir := away.rotated(k * 0.6)
		if _los(me, me + dir * 90.0):
			return dir
	return away.orthogonal()


func _avoid_walls(dir: Vector2) -> Vector2:
	var me := player.global_position
	if dir == Vector2.ZERO or _los(me, me + dir.normalized() * 60.0):
		return dir
	_strafe_sign = -_strafe_sign
	return -dir


# --- Fin --------------------------------------------------------------------------------

func _end_from_raid() -> void:
	if not player.is_alive() and not shots_dir.is_empty():
		_shot("mort_" + last_hit_kind)
	if not player.is_alive():
		outcome = "mort"
		killer = last_hit_kind
		var boss := _boss_node()
		if boss != null:
			phase_deaths = int(boss.boss_phase) + 1 if boss.boss_phase >= 0 else int(boss.phase)
			boss_info["hp_ratio_at_death"] = snappedf(boss.hp / maxf(boss.max_hp, 1.0), 0.001)
			boss_info["death_skill"] = death_skill
	elif outcome.is_empty():
		outcome = "extraction"
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(move_stick) and is_instance_valid(aim_stick):
		_sticks(Vector2.ZERO, Vector2.ZERO)
	var ttk_avg := {}
	for k: String in ttk:
		var arr: Array = ttk[k]
		var s := 0.0
		for v: float in arr:
			s += v
		ttk_avg[k] = snappedf(s / maxf(arr.size(), 1), 0.01)
	if mode == "boss":
		var boss := _boss_node()
		if boss != null:
			boss_info["hp_ratio_end"] = snappedf(boss.hp / maxf(boss.max_hp, 1.0), 0.001)
		boss_info["killed"] = bool(boss_info.get("killed", false))
	log.merge({
		"outcome": outcome, "killer": killer, "duration": snappedf(_death_t if _death_t >= 0.0 else t, 0.1),
		"hp_end": snappedf(player.hp if is_instance_valid(player) else 0.0, 0.1),
		"hp_min": snappedf(hp_min, 0.1),
		"damage_taken": _round_dict(dmg_taken), "hits_taken": hits_taken,
		"damage_dealt": _round_dict(dmg_dealt), "kills": kills, "ttk": ttk, "ttk_avg": ttk_avg,
		"seen": seen_kinds, "elites": elites_met, "boss": boss_info, "boss_phase_at_death": phase_deaths,
		"items": items, "item_ids": item_ids, "bag_value": bag_value, "gold_estimate": gold_estimate,
		"xp": Profile.raider_xp - _xp0, "shots": shots, "gadgets_used": gadgets_used, "heals_used": heals_used,
		"containers_opened": containers_opened, "corpses_searched": corpses_searched,
		"searches_cancelled": searches_cancelled, "floors": floors_visited.keys().filter(func(k: String) -> bool: return not k.begins_with("chk_")),
		"rooms_visited": _visited_rooms.size(), "stuck_enemies": stuck_enemies,
		"unreachable_containers": unreachable_containers, "unreachable_kinds": unreachable_kinds,
		"bot_stuck": bot_stuck, "dodges": dodges, "worst_frame_ms": snappedf(worst_frame_ms, 0.01),
		"avg_frame_ms": snappedf(frame_ms_sum / maxf(frames, 1), 0.01),
		"errors": errors, "warnings": warnings,
	})
	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var tmp := out_path + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(log, "  "))
			f.close()
			DirAccess.rename_absolute(tmp, out_path)
	print("PLAYTEST ", outcome, " ", snappedf(t, 0.1), "s")
	PlaytestProbe.enabled = false
	PlaytestProbe.sink = null
	# Joysticks virtuels (hors de l'arbre) libérés dès la fin : aucun nœud orphelin.
	if is_instance_valid(player):
		player.set_joysticks(null, null)
	for stick: Variant in [move_stick, aim_stick]:
		if is_instance_valid(stick):
			(stick as Node).free()
	finished.emit(log)
	if not embedded:
		get_tree().quit(0 if outcome != "erreur" else 2)


static func _round_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		out[k] = snappedf(float(d[k]), 0.1)
	return out
