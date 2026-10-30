class_name CoopRaid
extends Node
## Raid coop (enfant du nœud Raid, créé par NetHooks.attach_raid quand un raid est lancé
## depuis le salon). Même seed et même étage chez les deux joueurs ; l'HÔTE fait autorité.
##
## Autorité :
##  - Hôte : IA des ennemis et tourelles, dégâts (y compris ceux des tirs de l'invité, revalidés
##    en refaisant partir ses projectiles depuis l'avatar), morts, butin des cadavres.
##  - Invité : son propre déplacement (prédit localement, aucun retour en arrière), ses tirs
##    (visibles tout de suite, purement visuels chez lui), ses PV (dégâts reçus de l'hôte).
##    Les ennemis sont des « marionnettes » (Enemy.net_puppet) interpolées depuis les
##    instantanés de l'hôte ; ses dégâts locaux sont désactivés (NetHooks.guest_mode).
##  - Butin : tirages déterministes (seed, ordre des morts) des deux côtés ; seuls les
##    événements (fouille verrouillée, ouverture, objet pris, ramassage) sont échangés.
##    Fouille : un seul joueur à la fois (verrou arbitré par l'hôte, l'hôte gagne les égalités) ;
##    ce qui est pris va dans le sac de celui qui le prend.
##  - Portes : la première ouverture (ou déverrouillage) gagne, relayée à l'autre.
## Étages : changement COMMUN. Prendre un escalier lance un compte à rebours de
## [net] floor_countdown s chez les deux (l'invité le demande à l'hôte), puis les deux changent
## d'étage ensemble ; l'hôte n'a ainsi qu'un étage à simuler.
## Réseau : état du joueur [net] state_rate /s, ennemis proches du coéquipier [net] enemy_rate /s,
## événements regroupés en un paquet par image. Voir NetProtocol.

const WAIT_TIMEOUT := 30.0
const SET_AIM_INTERVAL_MS := 100

var raid: Raid = null
var session: NetSession = null
var is_host: bool = false
var local: Player = null
var avatar: CoopAvatar = null
var hud: CoopHud = null
var clock: SnapshotBuffer.ClockSync = SnapshotBuffer.ClockSync.new()
var local_status: int = CoopRules.Status.ALIVE
var partner_status: int = CoopRules.Status.ALIVE
var partner_connected: bool = true
var partner_name: String = "Coéquipier"
var abandoned: bool = false
## Le coéquipier a chargé le raid (RAID_HELLO reçu).
var peer_ready: bool = false
var waiting: bool = true
var spectating: bool = false
var final_shown: bool = false
## Statistiques (tests, debug F3).
var damage_sent: float = 0.0
var damage_received: float = 0.0
var remote_shots: int = 0
var enemy_snapshots: int = 0

var _w := NetProtocol.Writer.new()
var _ev := NetProtocol.Writer.new()
var _r := NetProtocol.Reader.new()
var _st := NetProtocol.PlayerState.new()
var _rst := NetProtocol.PlayerState.new()
var _state_interval: float = 0.05
var _enemy_interval: float = 0.0667
var _state_left: float = 0.0
var _enemy_left: float = 0.0
var _hello_left: float = 0.0
var _wait_left: float = WAIT_TIMEOUT
var _sync_radius2: float = 1800.0 * 1800.0
var _interp_delay_ms: float = 100.0
var _fired: bool = false
## Compteur des ennemis créés en cours de raid (renforts) : identités 30001, 30002…
var _dynamic_ids: int = 0
## Ennemis de l'étage courant : net_id → Enemy.
var _enemies: Dictionary = {}
## Hôte : dernière position envoyée par ennemi (filtre des ennemis immobiles).
var _last_sent: Dictionary = {}
var _last_aim_ms: Dictionary = {}
## Invité : pistes d'interpolation des marionnettes.
var _tracks: Dictionary = {}
var _puppet_vis_left: float = 0.0
var _downed_left: float = 0.0
var _revived_until_ms: int = 0
var _reviving: bool = false
var _revive_progress: float = 0.0
var _revive_send_left: float = 0.0
## Verrous de fouille : clef → 0 (hôte) / 1 (invité). Les miens : clef → conteneur.
var _locks: Dictionary = {}
var _my_locks: Dictionary = {}
var _lock_check_left: float = 0.25
var _lock_release_dist: float = 160.0
var _turret_left: float = 0.25
var _floor_countdown: float = -1.0
var _floor_target: int = 0
var _floor_cell: Vector2i = Vector2i.ZERO
var _allow_stairs: bool = false
var _pending_roster: PackedInt32Array = PackedInt32Array()
var _roster_all: bool = true
var _end_success: bool = false
var _end_summary: Dictionary = {}
var _end_pending: bool = false
var _avatar_c4: Array[GadgetDevice] = []
var _weapon_cache: Dictionary = {}
var _left_session: bool = false
var _note_left: float = 0.0


func setup(p_raid: Raid, p_session: NetSession) -> void:
	raid = p_raid
	session = p_session
	is_host = p_session.is_host()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10  # Avant les ennemis (positions des marionnettes).
	NetHooks.active = true
	NetHooks.is_host = is_host
	NetHooks.guest_mode = not is_host
	NetHooks.coop = self
	_load_balance()
	local = raid.player as Player
	var pinfo: Dictionary = session.peer_info
	if not pinfo.has("where"):
		pinfo["where"] = "raid"  # le coéquipier est en raid (pas encore revenu au salon)
	partner_name = String(pinfo.get("name", session.peer_name if session.peer_name != "" else "Coéquipier"))
	avatar = CoopAvatar.create(partner_name, StringName(String(pinfo.get("skin", ""))))
	avatar.coop = self
	avatar.clock = clock
	avatar.z_index = 10
	if local != null:
		avatar.position = local.position
	raid.level.add_child(avatar)
	_apply_peer_loadout_info(pinfo)
	NetHooks.targets.clear()
	if local != null:
		NetHooks.targets.append(local)
	NetHooks.targets.append(avatar)
	hud = CoopHud.new()
	hud.setup(self)
	add_child(hud)
	session.game_packet.connect(_on_packet)
	session.peer_left.connect(_on_peer_left)
	session.peer_lost.connect(_on_peer_lost)
	session.peer_back.connect(_on_peer_back)
	session.room_closed.connect(_on_room_closed)
	session.connection_lost.connect(_on_connection_lost)
	session.reconnected.connect(_on_reconnected)
	partner_connected = session.peer_connected
	EventBus.floor_changed.connect(_on_floor_changed)
	if local != null:
		local.weapons_changed.connect(_send_loadout)
		local.gadget_changed.connect(_send_loadout)
		local.fired.connect(func(_d: Vector2) -> void: _fired = true)
		local.set_physics_process(false)
	get_tree().node_added.connect(_on_node_added)
	for g: Node in get_tree().get_nodes_in_group(GroundLoot.GROUP):
		_on_node_added(g)
	_on_floor_changed(raid.current_floor)
	_send_loadout()
	_send_hello()
	hud.show_wait(true)
	for pkt: PackedByteArray in session.take_early_packets():
		_on_packet(pkt)


func _exit_tree() -> void:
	if NetHooks.coop == self:
		NetHooks.reset()
	if session != null and is_instance_valid(session):
		for sig: Array in [[session.game_packet, _on_packet], [session.peer_left, _on_peer_left],
				[session.peer_lost, _on_peer_lost], [session.peer_back, _on_peer_back],
				[session.room_closed, _on_room_closed], [session.connection_lost, _on_connection_lost],
				[session.reconnected, _on_reconnected]]:
			var s: Signal = sig[0]
			if s.is_connected(sig[1]):
				s.disconnect(sig[1])
		if not _left_session and session.in_room() and not session.replay_requested:
			session.leave()
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _load_balance() -> void:
	_state_interval = 1.0 / maxf(Balance.get_float("net", "state_rate", 20.0), 1.0)
	_enemy_interval = 1.0 / maxf(Balance.get_float("net", "enemy_rate", 15.0), 1.0)
	var r := Balance.get_float("net", "enemy_sync_radius", 1800.0)
	_sync_radius2 = r * r
	_interp_delay_ms = Balance.get_float("net", "interp_delay", 0.1) * 1000.0
	_lock_release_dist = Balance.get_float("net", "lock_release_distance", 160.0)


func is_partner_in_raid() -> bool:
	return partner_connected and CoopRules.in_raid(partner_status)


# --- Boucle ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Le coop ne se met jamais en pause (menu pause, inventaire, carte) : le coéquipier joue.
	# Écran de fin affiché pendant que le coéquipier joue encore : l'hôte garde le raid en marche
	# (ennemis, portes, tirs) derrière l'écran, sinon le monde de l'invité se fige.
	if get_tree().paused and (not final_shown or keeps_world_running()):
		get_tree().paused = false
	_flush_events()
	if final_shown:
		_note_left -= _delta
		if _note_left <= 0.0:
			_note_left = 0.4
			_update_end_note()


func _physics_process(delta: float) -> void:
	if waiting:
		_wait_left -= delta
		_hello_left -= delta
		if _hello_left <= 0.0:
			_send_hello()
		if peer_ready or _wait_left <= 0.0:
			_end_wait()
	if not is_host:
		_update_puppets(delta)
	_state_left -= delta
	if _state_left <= 0.0:
		_state_left += _state_interval
		if _state_left < 0.0:
			_state_left = _state_interval
		_send_state()
	if is_host:
		_enemy_left -= delta
		if _enemy_left <= 0.0:
			_enemy_left += _enemy_interval
			if _enemy_left < 0.0:
				_enemy_left = _enemy_interval
			_send_enemy_snapshot()
		_turret_left -= delta
		if _turret_left <= 0.0:
			_turret_left = 0.25
			_retarget_turrets()
	_tick_downed(delta)
	_tick_revive(delta)
	_tick_floor_countdown(delta)
	_lock_check_left -= delta
	if _lock_check_left <= 0.0:
		_lock_check_left = 0.25
		_check_locks()
	hud.tick(delta)


func _end_wait() -> void:
	waiting = false
	hud.show_wait(false)
	if not peer_ready:
		partner_status = CoopRules.Status.DISCONNECTED
		partner_connected = false
		avatar.set_gone(CoopRules.Status.LEFT)
		raid.show_toast("%s n'a pas rejoint le raid" % partner_name)
	if local != null and local_status == CoopRules.Status.ALIVE and not raid.is_raid_over():
		local.set_physics_process(true)


# --- Envoi ----------------------------------------------------------------------------

func _send_state() -> void:
	if local == null or not is_instance_valid(local):
		return
	_st.time_ms = NetProtocol.now_ms()
	_st.floor_index = raid.current_floor
	_st.position = local.global_position
	_st.velocity = local.velocity
	_st.aim = local.aim_direction
	var f := 0
	if local.is_moving():
		f |= NetProtocol.F_MOVING
	if local.is_aiming():
		f |= NetProtocol.F_AIMING
	if local.is_hidden():
		f |= NetProtocol.F_HIDDEN
	if local.net_downed:
		f |= NetProtocol.F_DOWNED
	if not local.is_alive() or local_status == CoopRules.Status.DEAD:
		f |= NetProtocol.F_DEAD
	if local_status == CoopRules.Status.EXTRACTED:
		f |= NetProtocol.F_EXTRACTED
	if local.is_reloading():
		f |= NetProtocol.F_RELOADING
	if _fired:
		f |= NetProtocol.F_FIRED
		_fired = false
	_st.flags = f
	_st.hp_ratio = local.hp / maxf(local.max_hp, 0.01)
	_st.slot = local.current_slot
	_w.clear()
	NetProtocol.write_state(_w, _st)
	session.send_game(_w.bytes(), false)


func _send_loadout() -> void:
	if local == null:
		return
	_ev.begin(NetProtocol.Msg.LOADOUT)
	_ev.text(session.player_name)
	_ev.text(String(Profile.skin_character))
	var ws := local.get_weapons()
	_ev.u8(ws.size())
	for w: WeaponData in ws:
		_ev.text(String(w.id) if w != null else "")
	_ev.u8(local.current_slot)
	var g := local.get_gadget()
	_ev.text(String(g.id) if g != null else "")
	_ev.u8(local.get_gadget_charges())
	_ev.f32(local.max_hp)
	# Skins d'armes (même ordre que les armes), en fin de message : une ancienne version les ignore.
	for sid: String in WeaponSkin.skin_ids_for(ws):
		_ev.text(sid)
	_ev.end()


func _send_hello() -> void:
	_hello_left = 1.0
	_ev.begin(NetProtocol.Msg.RAID_HELLO)
	_ev.u32(raid.run_seed)
	_ev.i8(raid.current_floor)
	_ev.u8(1 if peer_ready else 0)
	_ev.end()


func _send_player_evt(op: int, value: float = 0.0) -> void:
	_ev.begin(NetProtocol.Msg.PLAYER_EVT)
	_ev.u8(op)
	_ev.f32(value)
	_ev.end()


func _flush_events() -> void:
	if _ev.is_empty():
		return
	session.send_game(_ev.bytes(), true)
	_ev.clear()


## Instantané des ennemis proches du coéquipier (hôte → invité).
func _send_enemy_snapshot() -> void:
	if not is_partner_in_raid() or not avatar.has_state or _enemies.is_empty():
		return
	var ref := avatar.global_position
	var b := _w.buf
	_w.clear()
	NetProtocol.begin_enemy_snap(_w, NetProtocol.now_ms(), raid.current_floor, 0)
	var count_at := b.get_position() - 1
	var n := 0
	for id: int in _enemies:
		var ev: Variant = _enemies[id]
		if not is_instance_valid(ev):
			continue
		var e := ev as Enemy
		if not e.is_alive():
			continue
		var p := e.global_position
		if p.distance_squared_to(ref) > _sync_radius2:
			continue
		var last: Variant = _last_sent.get(id)
		if e.asleep and last is Vector2 and (last as Vector2).distance_squared_to(p) < 1.0:
			continue
		_last_sent[id] = p
		var fl := 0
		if e.velocity.length_squared() > 400.0:
			fl |= NetProtocol.EF_MOVING
		if e.is_in_combat():
			fl |= NetProtocol.EF_COMBAT
		NetProtocol.write_enemy(_w, id, p, e.facing, fl, e.hp / maxf(e.max_hp, 0.01), e.awareness)
		n += 1
		if n >= 200:
			break
	if n == 0:
		return
	var end_pos := b.get_position()
	b.seek(count_at)
	b.put_u8(n)
	b.seek(end_pos)
	_w.end()
	enemy_snapshots += 1
	session.send_game(_w.bytes(), false)


# --- Réception ------------------------------------------------------------------------

func _on_packet(data: PackedByteArray) -> void:
	_r.reset(data)
	NetHooks.applying_remote = true
	while true:
		var t := _r.next_msg()
		if t == 0:
			break
		_handle(t)
	NetHooks.applying_remote = false


func _handle(t: int) -> void:
	match t:
		NetProtocol.Msg.STATE:
			NetProtocol.read_state(_r, _rst)
			_on_partner_state(_rst)
		NetProtocol.Msg.LOADOUT:
			_on_loadout()
		NetProtocol.Msg.FIRE:
			_on_fire(NetProtocol.read_fire(_r))
		NetProtocol.Msg.ENEMY_SNAP:
			_on_enemy_snap()
		NetProtocol.Msg.ENEMY_FX:
			_on_enemy_fx()
		NetProtocol.Msg.ENEMY_DEATH:
			_on_enemy_death()
		NetProtocol.Msg.ENEMY_SHOT:
			_on_enemy_shot()
		NetProtocol.Msg.DYNAMITE:
			_on_dynamite()
		NetProtocol.Msg.DAMAGE:
			_on_damage()
		NetProtocol.Msg.STATUS:
			_on_status()
		NetProtocol.Msg.DOOR:
			_on_door()
		NetProtocol.Msg.CONTAINER:
			_on_container()
		NetProtocol.Msg.GROUND:
			_on_ground()
		NetProtocol.Msg.GADGET:
			_on_gadget_msg()
		NetProtocol.Msg.PLAYER_EVT:
			_on_player_evt()
		NetProtocol.Msg.FLOOR:
			_on_floor_msg()
		NetProtocol.Msg.TURRET:
			_on_turret_msg()
		NetProtocol.Msg.RAID_HELLO:
			_on_hello()


func _on_hello() -> void:
	var seed_v := _r.u32()
	var _floor := _r.i8()
	var they_ready := _r.u8() != 0
	if seed_v != (raid.run_seed & 0xFFFFFFFF):
		push_warning("Coop : seed différente (%d / %d)." % [seed_v, raid.run_seed])
		raid.show_toast("Désynchronisation : seeds différentes")
	if not peer_ready:
		peer_ready = true
		_send_hello()
		_send_loadout()
	elif not they_ready:
		_send_hello()


func _on_partner_state(s: NetProtocol.PlayerState) -> void:
	if s.floor_index != raid.current_floor or raid.is_transitioning():
		return
	if not avatar.has_meta(&"coop_gone"):
		avatar.apply_state(s)
		var downed := s.has(NetProtocol.F_DOWNED)
		if downed and partner_status == CoopRules.Status.ALIVE:
			partner_status = CoopRules.Status.DOWNED
		elif not downed and partner_status == CoopRules.Status.DOWNED:
			partner_status = CoopRules.Status.ALIVE
	else:
		clock.observe(s.time_ms, NetProtocol.now_ms())
	hud.set_partner_hp(s.hp_ratio)


func _on_loadout() -> void:
	var pname := _r.text()
	var skin := _r.text()
	var n := _r.u8()
	var ids: Array[String] = []
	for i: int in n:
		ids.append(_r.text())
	var slot := _r.u8()
	var gid := _r.text()
	var charges := _r.u8()
	var mhp := _r.f32()
	var skins: Array[String] = []
	for i: int in n:
		if _r.remaining() <= 0:
			break
		skins.append(_r.text())
	if pname != "":
		partner_name = pname
		avatar.peer_name = pname
		avatar.refresh_tag()
	avatar.set_skin(StringName(skin))
	avatar.apply_loadout(ids, slot, gid, charges, mhp, skins)
	hud.refresh_partner()


func _apply_peer_loadout_info(info: Dictionary) -> void:
	var lo: Variant = info.get("loadout", [])
	if lo is Array and not (lo as Array).is_empty():
		var ids: Array[String] = []
		for id: Variant in lo:
			ids.append(str(id))
		var skins: Array[String] = []
		var ws: Variant = info.get("wskins", [])
		if ws is Array:
			for s: Variant in ws:
				skins.append(str(s))
		avatar.apply_loadout(ids, 0, "", 0, -1.0, skins)


func _weapon_for(id: String) -> WeaponData:
	if _weapon_cache.has(id):
		return _weapon_cache[id]
	var w := WeaponCatalog.get_weapon(StringName(id))
	if w == null:
		w = Player.load_default_weapon()
	# Hôte : bonus de dégâts de la carte appliqué aux tirs de l'invité aussi.
	if is_host and raid.map_card != null:
		var m: float = maxf(raid.map_card.get_mod_f("player_damage_mult"), 0.0)
		if not is_equal_approx(m, 1.0) and m > 0.0:
			w = w.duplicate() as WeaponData
			w.damage *= m
			w.explosion_damage *= m
	_weapon_cache[id] = w
	return w


# --- Tirs -----------------------------------------------------------------------------

## ProjectilePool.spawn (via NetHooks).
func on_player_projectile(p: Node2D, pos: Vector2, dir: Vector2, weapon: WeaponData, source: Node, height: float) -> void:
	if weapon == null or local == null or source != local:
		return  # Tirs de l'avatar (déjà relayés) ou d'une autre source.
	if not is_partner_in_raid():
		return
	var homing := false
	if p is Projectile:
		homing = (p as Projectile)._homing_rate > 0.0
	NetProtocol.write_fire(_ev, String(weapon.id), pos, dir, height, homing)


func _on_fire(d: Dictionary) -> void:
	var w := _weapon_for(String(d["weapon"]))
	var dir: Vector2 = d["dir"]
	remote_shots += 1
	if avatar.has_meta(&"coop_gone"):
		return
	var pool := avatar.projectile_pool
	if pool != null:
		var p := pool.spawn(d["origin"], dir, w, avatar, float(d["height"]))
		if p != null and bool(d["homing"]) and is_host:
			var target := avatar.find_homing_target(dir)
			if target != null:
				p.set_homing(target, Player.weapon_homing(w))
	avatar.remote_fired(dir, w)


## EnemyProjectilePool.spawn chez l'hôte : visuel chez l'invité s'il est proche.
func on_enemy_projectile(pos: Vector2, dir: Vector2, speed: float, life: float, style: StringName) -> void:
	if not is_partner_in_raid() or pos.distance_squared_to(avatar.global_position) > _sync_radius2:
		return
	_ev.begin(NetProtocol.Msg.ENEMY_SHOT)
	_ev.pos(pos)
	_ev.u16(NetProtocol.q_angle16(dir.angle()))
	_ev.u16(clampi(roundi(speed), 0, 65535))
	_ev.u8(clampi(roundi(life * 20.0), 1, 255))
	_ev.text(String(style))
	_ev.end()


func _on_enemy_shot() -> void:
	var pos := _r.pos()
	var dir := Vector2.from_angle(NetProtocol.dq_angle16(_r.u16()))
	var speed := float(_r.u16())
	var life := float(_r.u8()) / 20.0
	var style := StringName(_r.text())
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	if pool != null:
		pool.spawn(pos, dir, speed, 0.0, null, life, style)


func on_enemy_dynamite(from: Vector2, to: Vector2, radius: float, flight: float, fuse: float) -> void:
	if not is_partner_in_raid():
		return
	_ev.begin(NetProtocol.Msg.DYNAMITE)
	_ev.pos(from)
	_ev.pos(to)
	_ev.u16(clampi(roundi(radius), 0, 65535))
	_ev.u8(clampi(roundi(flight * 20.0), 1, 255))
	_ev.u8(clampi(roundi(fuse * 20.0), 1, 255))
	_ev.end()


func _on_dynamite() -> void:
	var from := _r.pos()
	var to := _r.pos()
	var radius := float(_r.u16())
	var flight := float(_r.u8()) / 20.0
	var fuse := float(_r.u8()) / 20.0
	if raid.enemies_container != null:
		EnemyDynamite.throw(raid.enemies_container, from, to, radius, 0.0, flight, fuse, null)


# --- Dégâts et « à terre » --------------------------------------------------------------

## Hôte : l'avatar de l'invité est touché → l'invité applique les dégâts à son joueur.
func on_avatar_damaged(amount: float, source: Node) -> void:
	damage_sent += amount
	_ev.begin(NetProtocol.Msg.DAMAGE)
	_ev.f32(amount)
	_ev.pos((source as Node2D).global_position if source is Node2D and is_instance_valid(source) else avatar.global_position)
	_ev.end()


func _on_damage() -> void:
	var amount := _r.f32()
	var _src := _r.pos()
	damage_received += amount
	if local != null and local_status == CoopRules.Status.ALIVE:
		local.take_damage(amount, null)


## Hôte : un statut (compétence ennemie) frappe l'avatar → l'invité l'applique à son joueur.
func on_avatar_status(kind: StringName, duration: float, strength: float, from: Vector2) -> void:
	_ev.begin(NetProtocol.Msg.STATUS)
	_ev.text(String(kind))
	_ev.u8(clampi(roundi(duration * 20.0), 1, 255))
	_ev.u8(clampi(roundi(strength * 50.0), 0, 255))
	_ev.pos(from if from != Vector2.INF else avatar.global_position)
	_ev.end()


func _on_status() -> void:
	var kind := StringName(_r.text())
	var duration := float(_r.u8()) / 20.0
	var strength := float(_r.u8()) / 50.0
	var from := _r.pos()
	if local != null and local_status == CoopRules.Status.ALIVE:
		local.apply_status(kind, duration, strength, from)


## Ennemi créé en cours de raid (renforts) : enregistré sous une identité réseau commune.
func register_dynamic_enemy(e: Node2D, id: int) -> int:
	var en := e as Enemy
	if en == null:
		return -1
	if id < 0:
		_dynamic_ids += 1
		id = 30000 + _dynamic_ids
	en.set_meta(&"net_id", id)
	_enemies[id] = en
	if is_host:
		if not en.died.is_connected(_on_host_enemy_died):
			en.died.connect(_on_host_enemy_died)
	else:
		_make_puppet(en)
	return id


## Joueur local à 0 PV (Player.take_damage) : à terre si le coéquipier peut le relever.
func on_local_lethal(p: Player) -> bool:
	if p != local or local_status != CoopRules.Status.ALIVE:
		return false
	if not CoopRules.should_go_down(partner_status, partner_connected):
		return false
	local_status = CoopRules.Status.DOWNED
	p.net_downed = true
	p.hp = 0.0
	p.velocity = Vector2.ZERO
	if p.is_reloading():
		p.loadout.cancel_reload()
	if p.is_hidden():
		p.set_hidden(false)
	if p.visual != null:
		p.visual.modulate = Color(1.0, 0.55, 0.55, 0.9)
		p.visual.hp_dirty()
	raid._cancel_extraction(false)
	_downed_left = CoopRules.downed_time()
	_send_player_evt(NetProtocol.PlayerOp.DOWNED)
	hud.show_downed(true)
	return true


func _tick_downed(delta: float) -> void:
	if local_status != CoopRules.Status.DOWNED:
		return
	var revived := Time.get_ticks_msec() < _revived_until_ms
	_downed_left = CoopRules.step_downed(_downed_left, delta, revived)
	hud.set_downed_time(_downed_left)
	if _downed_left <= 0.0:
		_bleed_out()


## Pas relevé à temps : mort (flux normal du raid : Profile.finish_death, puis spectateur).
func _bleed_out() -> void:
	if local == null:
		return
	local_status = CoopRules.Status.DEAD
	local.net_downed = false
	if local.visual != null:
		local.visual.modulate = Color.WHITE
	hud.show_downed(false)
	_send_player_evt(NetProtocol.PlayerOp.DEAD)
	local._die()


func _revive_local(ratio: float) -> void:
	if local == null or local_status != CoopRules.Status.DOWNED:
		return
	local_status = CoopRules.Status.ALIVE
	local.net_downed = false
	local.hp = local.max_hp * ratio
	if local.visual != null:
		local.visual.modulate = Color.WHITE
		local.visual.hp_dirty()
	hud.show_downed(false)
	EventBus.player_damaged.emit(0.0, local.hp, local.max_hp)
	raid.show_toast("%s t'a relevé !" % partner_name)


func can_revive() -> bool:
	return local != null and local_status == CoopRules.Status.ALIVE and local.is_alive() and not local.net_downed


func is_reviving() -> bool:
	return _reviving


func begin_revive() -> void:
	if not can_revive() or not avatar.net_downed:
		return
	_reviving = true
	_revive_progress = 0.0
	_revive_send_left = 0.0


func end_revive() -> void:
	if not _reviving:
		return
	_reviving = false
	avatar.revive_ratio = -1.0
	avatar.refresh_tag()
	_send_player_evt(NetProtocol.PlayerOp.REVIVE_PROGRESS, -1.0)


func _tick_revive(delta: float) -> void:
	if not _reviving:
		return
	var dist := local.global_position.distance_to(avatar.global_position)
	var prog := CoopRules.step_revive(_revive_progress, delta, dist, can_revive(), avatar.net_downed)
	if prog < 0.0:
		end_revive()
		return
	_revive_progress = prog
	avatar.revive_ratio = prog
	avatar.refresh_tag()
	_revive_send_left -= delta
	if _revive_send_left <= 0.0:
		_revive_send_left = 0.2
		_send_player_evt(NetProtocol.PlayerOp.REVIVE_PROGRESS, prog)
	if prog >= 1.0:
		_reviving = false
		_send_player_evt(NetProtocol.PlayerOp.REVIVED, CoopRules.revive_hp_ratio())
		avatar.set_downed(false)
		partner_status = CoopRules.Status.ALIVE
		hud.refresh_partner()
		raid.show_toast("Tu as relevé %s !" % partner_name)


func _on_player_evt() -> void:
	var op := _r.u8()
	var value := _r.f32()
	match op:
		NetProtocol.PlayerOp.DOWNED:
			partner_status = CoopRules.Status.DOWNED
			avatar.set_downed(true)
			raid.show_toast("%s est à terre ! Va le relever." % partner_name)
		NetProtocol.PlayerOp.REVIVE_PROGRESS:
			if value >= 0.0:
				_revived_until_ms = Time.get_ticks_msec() + 450
			else:
				_revived_until_ms = 0
			hud.set_revive_progress(value)
		NetProtocol.PlayerOp.REVIVED:
			_revive_local(value)
		NetProtocol.PlayerOp.DEAD:
			_partner_gone(CoopRules.Status.DEAD, "%s est mort." % partner_name)
		NetProtocol.PlayerOp.EXTRACTED:
			_partner_gone(CoopRules.Status.EXTRACTED, "%s s'est extrait !" % partner_name)
		NetProtocol.PlayerOp.LEFT:
			_partner_gone(CoopRules.Status.LEFT, "%s a quitté le raid." % partner_name)
	hud.refresh_partner()


func _partner_gone(st: int, msg: String) -> void:
	if not CoopRules.in_raid(partner_status):
		return  # Déjà sorti (extrait, mort…) : le premier statut final fait foi.
	partner_status = st
	avatar.set_gone(st)
	if _reviving:
		end_revive()
	raid.show_toast(msg)
	hud.refresh_partner()
	if spectating:
		_show_final()
	elif final_shown:
		_update_end_note()


# --- Fin de raid, spectateur ----------------------------------------------------------

## Raid._show_end_screen : mort / extraction locale déjà soldée côté Profile.
func defer_end_screen(success: bool, summary: Dictionary) -> bool:
	if _end_pending:
		return final_shown
	_end_pending = true
	_end_success = success
	_end_summary = summary
	local_status = CoopRules.Status.EXTRACTED if success else CoopRules.Status.DEAD
	_send_player_evt(NetProtocol.PlayerOp.EXTRACTED if success else (NetProtocol.PlayerOp.LEFT if abandoned else NetProtocol.PlayerOp.DEAD))
	_send_state()
	_flush_events()
	if local != null:
		local.set_meta(&"coop_gone", true)
		if success:
			local.visible = false
			local.collision_layer = 0
	if _reviving:
		end_revive()
	hud.show_downed(false)
	if CoopRules.should_spectate(partner_status, partner_connected, abandoned) and avatar.has_state:
		_enter_spectator()
		return true
	final_shown = true
	session.set_local_where("end")
	return false


func _enter_spectator() -> void:
	spectating = true
	avatar.set_spectated(true)
	hud.show_spectator(true)


## Le joueur spectateur quitte : écran de fin.
func quit_spectating() -> void:
	_show_final()


func _show_final() -> void:
	if final_shown:
		return
	final_shown = true
	spectating = false
	hud.show_spectator(false)
	if avatar != null:
		avatar.set_spectated(false)
	if local != null and local.camera != null:
		local.camera.make_current()
	var end := RaidEndScreen.create(_end_success, _end_summary)
	raid.end_screen = end
	raid.add_child(end)
	_flush_events()
	session.set_local_where("end")
	_update_end_note()


## Le salon reste ouvert tant que l'écran de fin est affiché (il était quitté 0,6 s après la fin :
## l'hôte qui finissait le premier fermait alors le salon et coupait le raid de l'invité, qui
## n'avait jamais son écran de fin). On le quitte en sortant de la scène (_exit_tree).
## Hôte : le raid continue derrière l'écran de fin tant que l'invité y est encore.
func keeps_world_running() -> bool:
	return is_host and CoopRules.in_raid(partner_status)


## « Rejouer ensemble » possible : les deux ont fini et le coéquipier est encore dans le salon.
func can_replay() -> bool:
	return final_shown and session != null and is_instance_valid(session) and session.in_room() \
		and session.peer_present and not CoopRules.in_raid(partner_status)


## Retour au salon avec la même équipe (l'écran de fin change de scène juste après).
func request_replay() -> bool:
	if not can_replay():
		return false
	session.replay_requested = true
	_left_session = true
	return true


## Ligne d'information sous les boutons de l'écran de fin (coéquipier encore en raid).
func _update_end_note() -> void:
	var end := raid.end_screen if raid != null else null
	if end == null or not is_instance_valid(end):
		return
	var t := ""
	if not session.in_room() or not session.peer_present:
		t = "%s a quitté le salon." % partner_name
	elif session.peer_where() == "lobby":
		t = "%s t'attend au salon." % partner_name
	if CoopRules.in_raid(partner_status) and partner_connected:
		t = ("%s est encore en raid : reste sur cet écran, le quitter met fin à sa partie." if is_host
			else "%s est encore en raid.") % partner_name
	end.set_note(t)
	end.set_replay(can_replay())
	if not end.replay_pressed.is_connected(_on_replay_pressed):
		end.replay_pressed.connect(_on_replay_pressed)


func _on_replay_pressed() -> void:
	var end := raid.end_screen if raid != null else null
	if request_replay() and end != null and is_instance_valid(end):
		end.go_to_menu(MenuKit.COOP_SCENE)


func view_position(default: Vector2) -> Vector2:
	if spectating and avatar != null and avatar.visible:
		return avatar.global_position
	return default


# --- Connexion ------------------------------------------------------------------------

func _on_peer_lost(_grace: float) -> void:
	partner_connected = false
	hud.refresh_partner()
	raid.show_toast("Connexion de %s perdue…" % partner_name)


func _on_peer_back() -> void:
	partner_connected = true
	hud.refresh_partner()
	raid.show_toast("%s est de retour" % partner_name)


## Hôte : l'invité est parti ou n'est pas revenu à temps (= considéré comme mort chez lui).
func _on_peer_left(reason: String) -> void:
	partner_connected = false
	var st := CoopRules.Status.DISCONNECTED if reason == "timeout" else CoopRules.Status.LEFT
	_partner_gone(st, ("Connexion de %s perdue : considéré comme mort." if reason == "timeout" else "%s a quitté le raid.") % partner_name)


func _on_connection_lost() -> void:
	hud.set_connection_text("Reconnexion au serveur…")


func _on_reconnected() -> void:
	hud.set_connection_text("")
	partner_connected = session.peer_connected
	hud.refresh_partner()


## Salon fermé (hôte parti, reprise impossible…).
func _on_room_closed(reason: String) -> void:
	hud.set_connection_text("")
	partner_connected = false
	_left_session = true
	if is_host:
		_partner_gone(CoopRules.Status.DISCONNECTED, "Connexion au serveur perdue : tu continues seul.")
		NetHooks.guest_mode = false
		return
	if raid.is_raid_over():
		partner_status = CoopRules.Status.DISCONNECTED
		if spectating:
			_show_final()
		return
	if CoopRules.guest_outcome(reason) == &"keep_arsenal":
		_end_host_lost()
	else:
		partner_status = CoopRules.Status.DISCONNECTED
		raid._finish_death()


## Invité, hôte disparu : fin du raid, arsenal emporté conservé, butin perdu.
func _end_host_lost() -> void:
	partner_status = CoopRules.Status.DISCONNECTED
	raid._raid_over = true
	raid._cancel_extraction(false)
	var summary := CoopRules.apply_host_lost(Profile, GameState.raid_inventory)
	raid._end_raid_state()
	final_shown = true
	_end_pending = true
	hud.show_host_lost(summary)


# --- Étages ---------------------------------------------------------------------------

## Raid._on_stairs_entered : changement d'étage commun avec compte à rebours.
func intercept_stairs(stairs: Variant) -> bool:
	if _allow_stairs or not is_partner_in_raid():
		return false
	var f := int(stairs.get("target_floor"))
	var c: Vector2i = stairs.get("target_cell")
	if not raid.has_floor(f):
		return false
	raid._stairs_cooldown = Balance.get_float("net", "floor_countdown", 3.0) + 1.0
	if _floor_countdown >= 0.0:
		return true
	if is_host:
		_start_floor_countdown(f, c)
	else:
		_ev.begin(NetProtocol.Msg.FLOOR)
		_ev.u8(NetProtocol.FloorOp.REQUEST)
		_ev.i8(f)
		_ev.i16(c.x)
		_ev.i16(c.y)
		_ev.f32(0.0)
		_ev.u16(0)
		_ev.end()
		raid.show_toast("Changement d'étage demandé…")
	return true


func _start_floor_countdown(f: int, c: Vector2i) -> void:
	var secs := maxf(Balance.get_float("net", "floor_countdown", 3.0), 0.0)
	_floor_countdown = secs
	_floor_target = f
	_floor_cell = c
	_ev.begin(NetProtocol.Msg.FLOOR)
	_ev.u8(NetProtocol.FloorOp.COUNTDOWN)
	_ev.i8(f)
	_ev.i16(c.x)
	_ev.i16(c.y)
	_ev.f32(secs)
	_ev.u16(0)
	_ev.end()


func _tick_floor_countdown(delta: float) -> void:
	if _floor_countdown < 0.0:
		return
	_floor_countdown = maxf(_floor_countdown - delta, 0.0)
	hud.set_countdown("%s dans %d…" % [raid.world_floor_name(_floor_target), ceili(_floor_countdown)])
	if _floor_countdown > 0.0 or not is_host:
		return
	# Hôte : ennemis vivants de l'étage cible (étage déjà visité) puis départ commun.
	_ev.begin(NetProtocol.Msg.FLOOR)
	_ev.u8(NetProtocol.FloorOp.GO)
	_ev.i8(_floor_target)
	_ev.i16(_floor_cell.x)
	_ev.i16(_floor_cell.y)
	_ev.f32(0.0)
	var st: FloorState = raid.floor_states.get(_floor_target) as FloorState
	if st == null:
		_ev.u16(NetProtocol.ROSTER_ALL)
	else:
		_ev.u16(st.enemies.size())
		for e: Dictionary in st.enemies:
			_ev.u16(int(e.get("net_id", 0)))
	_ev.end()
	_flush_events()
	_do_floor_change(_floor_target, _floor_cell)


func _on_floor_msg() -> void:
	var op := _r.u8()
	var f := _r.i8()
	var c := Vector2i(_r.i16(), _r.i16())
	var secs := _r.f32()
	var n := _r.u16()
	match op:
		NetProtocol.FloorOp.REQUEST:
			if is_host and _floor_countdown < 0.0 and raid.has_floor(f):
				_start_floor_countdown(f, c)
		NetProtocol.FloorOp.COUNTDOWN:
			_floor_countdown = secs
			_floor_target = f
			_floor_cell = c
		NetProtocol.FloorOp.GO:
			_roster_all = n == NetProtocol.ROSTER_ALL
			_pending_roster.clear()
			if not _roster_all:
				for i: int in n:
					_pending_roster.append(_r.u16())
			_do_floor_change(f, c)
		NetProtocol.FloorOp.CANCEL:
			_floor_countdown = -1.0
			hud.set_countdown("")


func _do_floor_change(f: int, c: Vector2i) -> void:
	_floor_countdown = -1.0
	hud.set_countdown("")
	if f == raid.current_floor or raid.is_transitioning():
		return
	_allow_stairs = true
	raid._stairs_cooldown = 0.0
	raid._on_stairs_entered({"target_floor": f, "target_cell": c})
	_allow_stairs = false


func _on_floor_changed(_index: int) -> void:
	_tracks.clear()
	_last_sent.clear()
	_last_aim_ms.clear()
	_locks.clear()
	_my_locks.clear()
	_avatar_c4.clear()
	_index_enemies()
	_scale_enemies(raid.floor_states.has(raid.current_floor))
	if is_host:
		for id: int in _enemies:
			var e := _enemies[id] as Enemy
			if not e.died.is_connected(_on_host_enemy_died):
				e.died.connect(_on_host_enemy_died)
		for node: Variant in raid._turret_cells:
			var t := node as Node
			if t != null and t.has_signal(&"destroyed"):
				var cell: Vector2i = raid._turret_cells[node]
				t.connect(&"destroyed", _on_host_turret_destroyed.bind(cell).unbind(1), CONNECT_ONE_SHOT)
	else:
		for id: int in _enemies.keys():
			var e := _enemies[id] as Enemy
			if not _roster_all and not _pending_roster.has(id):
				_enemies.erase(id)
				e.queue_free()
				continue
			_make_puppet(e)
		_roster_all = true
		_pending_roster.clear()
		for node: Variant in raid._turret_cells:
			_freeze_turret(node as Node)
	if avatar != null:
		avatar.buffer.clear()
		avatar.has_state = false
		if not avatar.has_meta(&"coop_gone"):
			avatar.visible = false
	if local != null and (local_status == CoopRules.Status.DEAD or local_status == CoopRules.Status.EXTRACTED):
		local.set_physics_process(false)


func _index_enemies() -> void:
	_enemies.clear()
	if raid.enemies_container == null:
		return
	var i := 0
	for n: Node in raid.enemies_container.get_children():
		var e := n as Enemy
		if e == null or e.is_queued_for_deletion():
			continue
		var id := int(e.get_meta(&"net_id", -1))
		if id < 0:
			id = 10000 + i
			e.set_meta(&"net_id", id)
		_enemies[id] = e
		i += 1


## PV et dégâts ennemis selon le barème [coop] enemy_hp_<n> / enemy_damage_<n> (une fois par
## ennemi ; étage restauré : PV déjà mis à l'échelle lors de la visite précédente). Le nombre
## d'ennemis, lui, est ajusté à la génération (Raid._apply_map_modifiers, enemy_density_<n>).
func _scale_enemies(restored: bool) -> void:
	var n := raid.party_size if raid != null else 2
	var m := CoopRules.party_mult("enemy_hp", n)
	var dm := CoopRules.party_mult("enemy_damage", n)
	if is_equal_approx(m, 1.0) and is_equal_approx(dm, 1.0):
		return
	for id: int in _enemies:
		var e := _enemies[id] as Enemy
		if e.has_meta(&"coop_scaled"):
			continue
		e.set_meta(&"coop_scaled", true)
		e.diff_damage_mult *= dm
		var ratio := e.hp / maxf(e.max_hp, 0.01)
		e.max_hp *= m
		e.hp = minf(e.hp, e.max_hp) if restored else e.max_hp * ratio


# --- Ennemis : hôte -------------------------------------------------------------------

func _on_host_enemy_died(e: Enemy) -> void:
	var id := int(e.get_meta(&"net_id", -1))
	_enemies.erase(id)
	_last_sent.erase(id)
	if id < 0 or not is_partner_in_raid():
		return
	_ev.begin(NetProtocol.Msg.ENEMY_DEATH)
	_ev.u16(id)
	_ev.pos(e.global_position)
	_ev.end()


func on_enemy_visual(e: Node2D, method: StringName, args: Array) -> void:
	var idx := NetProtocol.fx_index(method)
	if idx < 0 or not is_partner_in_raid():
		return
	var id := int(e.get_meta(&"net_id", -1))
	if id < 0 or e.global_position.distance_squared_to(avatar.global_position) > _sync_radius2:
		return
	if method == &"set_aim_direction":
		var now := Time.get_ticks_msec()
		if now - int(_last_aim_ms.get(id, -100000)) < SET_AIM_INTERVAL_MS:
			return
		_last_aim_ms[id] = now
	_ev.begin(NetProtocol.Msg.ENEMY_FX)
	_ev.u16(id)
	_ev.u8(idx)
	_ev.blob(var_to_bytes(args) if not args.is_empty() else PackedByteArray())
	_ev.end()


func _retarget_turrets() -> void:
	for t: Node2D in raid.get_alive_turrets():
		var cur: Variant = t.get(&"_player")
		var best := NetHooks.enemy_target(t, cur as Node2D if cur is Node2D else null)
		if best != null:
			t.set(&"_player", best)


func _on_host_turret_destroyed(cell: Vector2i) -> void:
	if not is_partner_in_raid():
		return
	_ev.begin(NetProtocol.Msg.TURRET)
	_ev.u8(NetProtocol.TurretOp.DESTROYED)
	_ev.i16(cell.x)
	_ev.i16(cell.y)
	_ev.end()


# --- Ennemis : invité (marionnettes) --------------------------------------------------

## Piste d'interpolation d'une marionnette (deux derniers instantanés).
class Track extends RefCounted:
	var e: Enemy = null
	var t0: int = 0
	var p0: Vector2 = Vector2.ZERO
	var t1: int = 0
	var p1: Vector2 = Vector2.ZERO
	var n: int = 0
	var facing_q: int = -1
	var moving: bool = false
	var hp_q: int = -1
	var aw_q: int = -1


func _make_puppet(e: Enemy) -> void:
	e.net_puppet = true
	e.velocity = Vector2.ZERO
	e.desired_velocity = Vector2.ZERO
	if e._sleep_timer != null:
		e._sleep_timer.stop()
	if e.asleep:
		e.wake_up()
	e.set_physics_process(false)


func _freeze_turret(t: Node) -> void:
	if t == null or not is_instance_valid(t):
		return
	t.set_physics_process(false)
	var timer: Variant = t.get(&"_sleep_timer")
	if timer is Timer:
		(timer as Timer).stop()


func _on_enemy_snap() -> void:
	var t := _r.u32()
	var f := _r.i8()
	var n := _r.u8()
	clock.observe(t, NetProtocol.now_ms())
	if f != raid.current_floor or raid.is_transitioning():
		return
	enemy_snapshots += 1
	for i: int in n:
		var id := _r.u16()
		var p := _r.pos()
		var fq := _r.u8()
		var fl := _r.u8()
		var hq := _r.u8()
		var aq := _r.u8()
		var tr: Track = _tracks.get(id) as Track
		if tr == null:
			var ev: Variant = _enemies.get(id)
			if not is_instance_valid(ev):
				continue
			tr = Track.new()
			tr.e = ev as Enemy
			_tracks[id] = tr
		if not is_instance_valid(tr.e):
			continue
		if not tr.e.is_alive():
			continue
		if tr.n == 0 or p.distance_to(tr.p1) > 300.0:
			tr.p0 = p
			tr.t0 = t - 1
			tr.e.global_position = p
			tr.e.reset_physics_interpolation()
		else:
			tr.p0 = tr.p1
			tr.t0 = tr.t1
		tr.p1 = p
		tr.t1 = t
		tr.n += 1
		tr.moving = (fl & NetProtocol.EF_MOVING) != 0
		if fq != tr.facing_q:
			tr.facing_q = fq
			tr.e._apply_facing(Vector2.from_angle(NetProtocol.dq_angle8(fq)))
		if hq != tr.hp_q:
			tr.hp_q = hq
			tr.e.hp = NetProtocol.dq_ratio(hq) * tr.e.max_hp
			if tr.e._health_bar != null:
				tr.e._health_bar.queue_redraw()
		if aq != tr.aw_q:
			tr.aw_q = aq
			tr.e.awareness = NetProtocol.dq_ratio(aq)
			if tr.e._awareness_bar != null:
				tr.e._awareness_bar.set_value(tr.e.awareness, (fl & NetProtocol.EF_COMBAT) == 0)


func _update_puppets(delta: float) -> void:
	if _tracks.is_empty() or not clock.has_offset:
		return
	var rt := clock.remote_now(NetProtocol.now_ms()) - _interp_delay_ms
	_puppet_vis_left -= delta
	var vis_check := _puppet_vis_left <= 0.0
	if vis_check:
		_puppet_vis_left = 0.5
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if not is_instance_valid(tr.e):
			continue
		var e := tr.e
		if not e.is_alive():
			continue
		var span := float(tr.t1 - tr.t0)
		var k := clampf((rt - float(tr.t0)) / maxf(span, 1.0), 0.0, 1.15)
		var p := tr.p0.lerp(tr.p1, k)
		e.global_position = p
		e.velocity = (tr.p1 - tr.p0) / maxf(span / 1000.0, 0.001) if tr.moving else Vector2.ZERO
		e._set_visual_moving(tr.moving and k < 1.1)
		if vis_check and e.visual != null and local != null:
			e.visual.set_process(e.global_position.distance_squared_to(local.global_position) < 2400.0 * 2400.0)


func _on_enemy_fx() -> void:
	var id := _r.u16()
	var idx := _r.u8()
	var b := _r.blob()
	var ev: Variant = _enemies.get(id)
	if not is_instance_valid(ev) or not (ev as Enemy).is_alive():
		return
	var e := ev as Enemy
	var args: Array = []
	if not b.is_empty():
		var v: Variant = bytes_to_var(b)
		if v is Array:
			args = v
	var m := NetProtocol.fx_method(idx)
	if m == &"play_shout" and not args.is_empty():
		e._visual_call(m, args)
		return
	if m != &"":
		e._visual_call(m, args)


func _on_enemy_death() -> void:
	var id := _r.u16()
	var p := _r.pos()
	var ev: Variant = _enemies.get(id)
	_tracks.erase(id)
	_enemies.erase(id)
	if not is_instance_valid(ev) or not (ev as Enemy).is_alive():
		return
	var e := ev as Enemy
	# Position exacte de l'hôte : cadavre et butin tirés au même endroit des deux côtés.
	e.global_position = p
	e.reset_physics_interpolation()
	e._die()


func _on_turret_msg() -> void:
	var op := _r.u8()
	var cell := Vector2i(_r.i16(), _r.i16())
	if op != NetProtocol.TurretOp.DESTROYED:
		return
	for node: Variant in raid._turret_cells:
		if raid._turret_cells[node] == cell and is_instance_valid(node):
			var t := node as Node
			if t.has_method(&"is_alive") and bool(t.call(&"is_alive")):
				t.call(&"_destroy", false)
			return


# --- Portes ---------------------------------------------------------------------------

func on_door_changed(door: Node2D) -> void:
	if not is_partner_in_raid():
		return
	var cell: Variant = door.get(&"cell")
	if not (cell is Vector2i):
		cell = FloorLayout.world_to_cell(door.global_position)
	var state := int(door.call(&"get_state")) if door.has_method(&"get_state") else (FloorLayout.DoorState.OPEN if bool(door.call(&"is_open")) else FloorLayout.DoorState.CLOSED)
	_ev.begin(NetProtocol.Msg.DOOR)
	_ev.i16((cell as Vector2i).x)
	_ev.i16((cell as Vector2i).y)
	_ev.u8(state)
	_ev.end()


func _on_door() -> void:
	var cell := Vector2i(_r.i16(), _r.i16())
	var state := _r.u8()
	var door := raid.get_door_at(cell)
	if door == null or not is_instance_valid(door):
		return
	if state == FloorLayout.DoorState.OPEN:
		if door.has_method(&"is_locked") and bool(door.call(&"is_locked")):
			door.call(&"try_unlock", door.get(&"key_id"))
		elif door.has_method(&"open"):
			door.call(&"open")
	elif state == FloorLayout.DoorState.CLOSED and door.has_method(&"close"):
		door.call(&"close")


# --- Conteneurs -----------------------------------------------------------------------

## Clef réseau d'un conteneur : clef de persistance (case) ou position (cadavres, sacoches).
static func container_key(c: Node2D) -> String:
	var lc := c as LootContainer
	if lc != null and lc.persist_key != "" and not lc.persist_key.begins_with("corpse:"):
		return lc.persist_key
	var fi := lc.floor_index if lc != null else 0
	return "p:%d:%d:%d" % [fi, roundi(c.global_position.x), roundi(c.global_position.y)]


func _find_container(key: String) -> LootContainer:
	for n: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		var c := n as LootContainer
		if c != null and not c.is_queued_for_deletion() and container_key(c) == key:
			return c
	return null


func _me() -> int:
	return 0 if is_host else 1


func _send_container(op: int, key: String, item: String = "", count: int = 0) -> void:
	_ev.begin(NetProtocol.Msg.CONTAINER)
	_ev.u8(op)
	_ev.text(key)
	_ev.text(item)
	_ev.u16(count)
	_ev.end()


## LootContainer.interact / start_search : un seul joueur à la fois.
func container_request(c: Node2D) -> bool:
	if local != null and local.net_downed:
		return false
	if not is_partner_in_raid():
		return true
	var key := container_key(c)
	var owner := int(_locks.get(key, -1))
	if owner >= 0 and owner != _me():
		raid.show_toast("%s fouille déjà" % partner_name)
		return false
	if owner != _me():
		_locks[key] = _me()
		_my_locks[key] = c
		_send_container(NetProtocol.ContainerOp.LOCK, key)
	return true


func container_opened(c: Node2D) -> void:
	if is_partner_in_raid():
		_send_container(NetProtocol.ContainerOp.OPENED, container_key(c))


func container_taken(c: Node2D, item_id: StringName, count: int) -> void:
	if is_partner_in_raid():
		_send_container(NetProtocol.ContainerOp.TAKEN, container_key(c), String(item_id), count)


func _on_container() -> void:
	var op := _r.u8()
	var key := _r.text()
	var item := _r.text()
	var count := _r.u16()
	var other := 1 - _me()
	match op:
		NetProtocol.ContainerOp.LOCK:
			if is_host and int(_locks.get(key, -1)) == 0:
				_send_container(NetProtocol.ContainerOp.DENY, key)
				return
			_locks[key] = other
			if _my_locks.has(key):
				# Égalité : l'hôte gagne.
				_lose_lock(key)
		NetProtocol.ContainerOp.DENY:
			_locks[key] = other
			_lose_lock(key)
		NetProtocol.ContainerOp.UNLOCK:
			if int(_locks.get(key, -1)) == other:
				_locks.erase(key)
		NetProtocol.ContainerOp.OPENED:
			var c := _find_container(key)
			if c != null:
				c.net_open_silently()
		NetProtocol.ContainerOp.TAKEN:
			var c2 := _find_container(key)
			if c2 != null:
				c2.net_remove(StringName(item), count)


func _lose_lock(key: String) -> void:
	var c: Variant = _my_locks.get(key)
	_my_locks.erase(key)
	if c is LootContainer and is_instance_valid(c) and (c as LootContainer).is_searching():
		(c as LootContainer).cancel_search()
	raid.show_toast("%s fouille déjà" % partner_name)


## Libère mes verrous : fouille annulée, conteneur vidé, ou joueur parti plus loin.
func _check_locks() -> void:
	if _my_locks.is_empty() or local == null:
		return
	for key: String in _my_locks.keys():
		var c: Variant = _my_locks[key]
		var release := not is_instance_valid(c)
		if not release:
			var lc := c as LootContainer
			release = lc.is_emptied() or (lc.state == LootContainer.State.CLOSED and not lc.is_searching()) \
				or lc.global_position.distance_to(local.global_position) > _lock_release_dist
		if release:
			_my_locks.erase(key)
			_locks.erase(key)
			_send_container(NetProtocol.ContainerOp.UNLOCK, key)


# --- Butin au sol ---------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	if n is GroundLoot:
		var g := n as GroundLoot
		if not g.picked.is_connected(_on_ground_picked):
			g.picked.connect(_on_ground_picked)


static func ground_key(g: Node2D) -> String:
	var gl := g as GroundLoot
	return "g:%d:%d:%d" % [gl.floor_index if gl != null else 0, roundi(g.position.x), roundi(g.position.y)]


func _on_ground_picked(g: GroundLoot, got: int) -> void:
	if NetHooks.applying_remote or not is_partner_in_raid() or g.item == null:
		return
	_ev.begin(NetProtocol.Msg.GROUND)
	_ev.text(ground_key(g))
	_ev.text(String(g.item.id))
	_ev.u16(got)
	_ev.end()


func _on_ground() -> void:
	var key := _r.text()
	var item := _r.text()
	var count := _r.u16()
	for n: Node in get_tree().get_nodes_in_group(GroundLoot.GROUP):
		var g := n as GroundLoot
		if g == null or g.is_queued_for_deletion() or g.item == null or String(g.item.id) != item:
			continue
		if ground_key(g) != key:
			continue
		g.count -= count
		g._notify_manager()
		if g.count <= 0:
			g.queue_free()
		else:
			g.queue_redraw()
		return


# --- Équipements ----------------------------------------------------------------------

func on_gadget(p: Node2D, w: WeaponData, op: StringName, from: Vector2, target: Vector2, height: float) -> void:
	if p != local or w == null or not is_partner_in_raid():
		return
	var code := NetProtocol.GadgetOp.THROW
	if op == &"drone":
		code = NetProtocol.GadgetOp.DRONE
	elif op == &"c4_detonate":
		code = NetProtocol.GadgetOp.C4_DETONATE
	_ev.begin(NetProtocol.Msg.GADGET)
	_ev.u8(code)
	_ev.text(String(w.id))
	_ev.pos(from)
	_ev.pos(target)
	_ev.u8(clampi(roundi(height), 0, 255))
	_ev.end()


func _on_gadget_msg() -> void:
	var op := _r.u8()
	var w := WeaponCatalog.get_weapon(StringName(_r.text()))
	var from := _r.pos()
	var to := _r.pos()
	var h := float(_r.u8())
	if avatar.has_meta(&"coop_gone"):
		return
	var parent: Node = avatar.projectile_pool.get_world_parent() if avatar.projectile_pool != null else raid.level
	match op:
		NetProtocol.GadgetOp.THROW:
			if w == null:
				return
			var dev := GadgetDevice.throw_device(parent, w, from, h, to, avatar, false)
			if w.gadget_kind == WeaponData.GADGET_C4:
				_avatar_c4.append(dev)
			if avatar.visual != null:
				avatar.visual.on_throw((to - from).normalized(), w)
		NetProtocol.GadgetOp.DRONE:
			# Hôte : les tirs du drone de l'invité arrivent comme des tirs (FIRE) ;
			# invité : drone visuel de l'hôte (ses tirs arrivent aussi en FIRE).
			if not is_host and w != null:
				var d := GadgetDrone.spawn(parent, avatar, w)
				d.net_visual_only = true
		NetProtocol.GadgetOp.C4_DETONATE:
			for d2: GadgetDevice in _avatar_c4:
				if is_instance_valid(d2):
					d2.detonate()
			_avatar_c4.clear()


# --- Debug ----------------------------------------------------------------------------

func get_debug_text() -> String:
	return "Coop %s · salon %s · ping %s · ↑%.1f ko ↓%.1f ko · marionnettes %d · moi %s · %s %s" % [
		"hôte" if is_host else "invité", session.room_code,
		("%d ms" % roundi(session.rtt_ms)) if session.rtt_ms >= 0.0 else "—",
		float(session.bytes_sent) / 1024.0, float(session.bytes_received) / 1024.0,
		_tracks.size(), CoopRules.status_text(local_status), partner_name, CoopRules.status_text(partner_status)]
