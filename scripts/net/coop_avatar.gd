class_name CoopAvatar
extends Player
## Coéquipier distant : même rendu que le joueur (PlayerVisual, skin du coéquipier, arme
## tenue), piloté par les états réseau (interpolés avec un léger retard, cf. SnapshotBuffer).
## Aucune entrée locale, aucune caméra active (sauf en mode spectateur).
## Hôte : cible des ennemis (groupe coop_avatar + damageable, couche player pour les balles
## ennemies) ; les dégâts reçus sont transmis à l'invité (CoopRaid.on_avatar_damaged).
## À terre : devient interactif (« Réanimer ») — maintenir l'action à côté.

const NAME_COLOR := Color(0.45, 0.9, 1.0)

var coop: CoopRaid = null
var peer_name: String = "Coéquipier"
var skin_id: StringName = &""
## Skins d'armes du coéquipier (String(id d'arme) → String(id de skin)) : ses armes sont habillées
## de SES skins, jamais de ceux du profil local.
var weapon_skin_ids: Dictionary = {}
var buffer: SnapshotBuffer = SnapshotBuffer.new()
var clock: SnapshotBuffer.ClockSync = null
var interp_delay_ms: float = 100.0
## Statut affiché (CoopRules.Status).
var partner_status: int = CoopRules.Status.ALIVE
## Progression de réanimation affichée (0..1, < 0 = aucune).
var revive_ratio: float = -1.0
var has_state: bool = false

var _out: PackedVector2Array = PackedVector2Array([Vector2.RIGHT, Vector2.ZERO])
var _tag: Node2D = null
var _fx_cool: float = 0.0
var _last_hp_q: int = -1
var _floor_index: int = 0


## Nœud prêt à ajouter (les enfants attendus par Player sont créés ici).
static func create(p_name: String, p_skin: StringName) -> CoopAvatar:
	var a := CoopAvatar.new()
	a.name = "CoopPartner"
	a.peer_name = p_name if p_name != "" else "Coéquipier"
	a.skin_id = p_skin
	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = Player.BODY_RADIUS
	cs.shape = circle
	a.add_child(cs)
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	cam.enabled = false
	a.add_child(cam)
	var pool := ProjectilePool.new()
	pool.name = "ProjectilePool"
	a.add_child(pool)
	return a


func _ready() -> void:
	# Remplace Player._ready : pas de groupe « player », pas de caméra courante, pas de
	# player_spawned (GameState.player reste le joueur local).
	add_to_group(NetHooks.GROUP_AVATAR)
	add_to_group(&"damageable")
	collision_layer = Player.LAYER_PLAYER
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_load_balance()
	hp = max_hp
	loadout.resize(int(Balance.get_value("arsenal", "loadout_slots", 3)))
	interp_delay_ms = Balance.get_float("net", "interp_delay", 0.1) * 1000.0
	buffer.extrapolate_max = Balance.get_float("net", "extrapolate_max", 0.15)
	visual = PlayerVisual.new()
	add_child(visual)
	with_partner_skin(func() -> void: visual.setup(self))
	visual.weapon_view.set_skin_ids(weapon_skin_ids)
	loadout.set_weapons([Player.load_default_weapon()])
	_on_weapon_changed(false)
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Balance.get_float("camera", "smoothing_speed", 7.0)
	var z: float = Balance.get_float("camera", "zoom", 1.1)
	_cam_base_zoom = Vector2(z, z)
	camera.zoom = _cam_base_zoom
	_tag = Node2D.new()
	_tag.name = "NameTag"
	_tag.z_as_relative = false
	_tag.z_index = 70
	_tag.position = Vector2(0.0, -(visual.body_height if visual != null else 60.0) - 30.0)
	_tag.draw.connect(_draw_tag)
	add_child(_tag)
	visible = false  # Jusqu'au premier état reçu.


## Applique temporairement le skin du coéquipier (le rendu lit le skin équipé du Profile).
func with_partner_skin(fn: Callable) -> void:
	var saved: StringName = Profile.skin_character
	if skin_id != &"" and SkinData.get_skin(skin_id) != null:
		Profile.skin_character = skin_id
	fn.call()
	Profile.skin_character = saved


## Change le skin affiché (reconstruit le visuel).
func set_skin(id: StringName) -> void:
	if id == skin_id or not is_inside_tree():
		skin_id = id
		return
	skin_id = id
	var old := visual
	visual = PlayerVisual.new()
	add_child(visual)
	with_partner_skin(func() -> void: visual.setup(self))
	visual.weapon_view.set_skin_ids(weapon_skin_ids)
	visual.set_weapon(weapon, false)
	if old != null:
		old.queue_free()


# --- Réseau ---------------------------------------------------------------------------

## Nouvel état reçu.
func apply_state(s: NetProtocol.PlayerState) -> void:
	if clock != null:
		clock.observe(s.time_ms, NetProtocol.now_ms())
	var teleport := buffer.push(s.time_ms, s.position, s.velocity, s.aim)
	_floor_index = s.floor_index
	if not has_state or teleport:
		has_state = true
		global_position = s.position
		reset_physics_interpolation()
		if camera.enabled:
			camera.reset_smoothing()
	var hidden_now := s.has(NetProtocol.F_HIDDEN)
	if hidden_now != _hidden:
		_hidden = hidden_now
		collision_layer = 0 if _hidden else Player.LAYER_PLAYER
		if visual != null:
			visual.refresh_state()
	var q := NetProtocol.q_ratio(s.hp_ratio)
	if q != _last_hp_q:
		_last_hp_q = q
		hp = s.hp_ratio * max_hp
		if visual != null:
			visual.hp_dirty()
	if s.has(NetProtocol.F_FIRED):
		_fire_noise = 1.0
	_aiming = s.has(NetProtocol.F_AIMING)
	var downed_now := s.has(NetProtocol.F_DOWNED)
	if downed_now != net_downed:
		set_downed(downed_now)
	if s.slot != loadout.current and s.slot < loadout.size():
		loadout.switch_to(s.slot)
		_on_weapon_changed(true)


## Armes tenues du coéquipier (ids), emplacement courant, équipement, skins d'armes (même ordre
## que `ids`, « » = aucun ; liste vide = aucun skin, ex. ancienne version).
func apply_loadout(ids: Array[String], slot: int, gadget_id: String, charges: int, p_max_hp: float,
		skins: Array[String] = []) -> void:
	weapon_skin_ids = WeaponSkin.skin_map(ids, skins)
	var list: Array[WeaponData] = []
	for id: String in ids:
		list.append(WeaponCatalog.get_weapon(StringName(id)) if id != "" else null)
	if list.is_empty() or list.all(func(w: WeaponData) -> bool: return w == null):
		list = [Player.load_default_weapon()]
	loadout.set_weapons(list)
	if slot >= 0 and slot < loadout.size():
		loadout.switch_to(slot)
	var g: WeaponData = WeaponCatalog.get_weapon(StringName(gadget_id)) if gadget_id != "" else null
	loadout.set_gadget(g)
	if g != null:
		loadout.gadget_charges = charges
	if p_max_hp > 0.0:
		max_hp = p_max_hp
	if visual != null and visual.weapon_view != null:
		visual.weapon_view.set_skin_ids(weapon_skin_ids)
	_on_weapon_changed(false)


## Tir du coéquipier (visuel : recul, éclair, son, douilles), limité à un effet par 50 ms.
func remote_fired(dir: Vector2, w: WeaponData) -> void:
	_fire_noise = 1.0
	if _fx_cool > 0.0 or visual == null or not visible:
		return
	_fx_cool = 0.05
	aim_direction = dir
	_on_fired_feel(w if w != null else weapon, dir)


func set_downed(on: bool) -> void:
	net_downed = on
	if on:
		partner_status = CoopRules.Status.DOWNED
		add_to_group(&"interactables")
	else:
		if partner_status == CoopRules.Status.DOWNED:
			partner_status = CoopRules.Status.ALIVE
		remove_from_group(&"interactables")
		revive_ratio = -1.0
	if visual != null:
		visual.modulate = Color(1.0, 0.55, 0.55, 0.85) if on else Color.WHITE
	refresh_tag()


## Mort ou parti : n'est plus une cible, s'efface.
func set_gone(status_value: int) -> void:
	partner_status = status_value
	set_meta(&"coop_gone", true)
	net_downed = false
	remove_from_group(&"interactables")
	remove_from_group(&"damageable")
	collision_layer = 0
	if status_value == CoopRules.Status.DEAD:
		_alive = false
		if visual != null:
			visual.refresh_state()
			visual.modulate = Color(0.6, 0.6, 0.7, 0.8)
		var tw := create_tween()
		tw.tween_interval(2.5)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
	else:
		visible = false
	refresh_tag()


func refresh_tag() -> void:
	if _tag != null:
		_tag.queue_redraw()


func get_floor_index() -> int:
	return _floor_index


# --- Boucle ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_fire_noise = maxf(_fire_noise - delta / maxf(noise_fire_decay, 0.01), 0.0)
	_fx_cool = maxf(_fx_cool - delta, 0.0)
	if not has_state or buffer.count == 0:
		return
	if not visible and not has_meta(&"coop_gone"):
		visible = true
	var t := (clock.remote_now(NetProtocol.now_ms()) if clock != null else float(buffer.latest_time())) - interp_delay_ms
	var p := buffer.sample(t, _out)
	global_position = p
	velocity = _out[1]
	if _out[0] != Vector2.ZERO:
		aim_direction = _out[0].normalized()
	_is_moving = velocity.length_squared() > 400.0 and not _hidden and not net_downed
	if camera.enabled:
		_update_camera(delta)


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _input(_event: InputEvent) -> void:
	pass


## Dégâts reçus chez l'hôte : transmis au coéquipier (qui gère ses PV et son « à terre »).
func take_damage(amount: float, source: Node) -> void:
	if not _alive or net_downed or amount <= 0.0 or _invulnerable_left > 0.0 or has_meta(&"coop_gone"):
		return
	if coop == null or not NetHooks.is_host:
		return
	_invulnerable_left = invulnerability_duration
	if visual != null:
		visual.on_hit()
	coop.on_avatar_damaged(amount, source)


## Statut infligé chez l'hôte (compétence ennemie) : affiché sur l'avatar et transmis au
## coéquipier, qui l'applique à son joueur.
func apply_status(kind: StringName, duration: float, strength: float = 1.0, from: Vector2 = Vector2.INF) -> void:
	if not _alive or net_downed or duration <= 0.0 or has_meta(&"coop_gone"):
		return
	if coop == null or not NetHooks.is_host:
		return
	if status == null:
		status = PlayerStatus.new()
		status.name = "Status"
		add_child(status)
	status.apply(kind, duration, strength)
	coop.on_avatar_status(kind, duration, strength, from)


## Spectateur : la caméra suit ce coéquipier.
func set_spectated(on: bool) -> void:
	camera.enabled = on
	if on:
		camera.make_current()
		camera.reset_smoothing()


# --- Réanimation (interactable quand le coéquipier est à terre) ------------------------

func can_interact() -> bool:
	return net_downed and coop != null and coop.can_revive()


func get_interact_label() -> String:
	return "Réanimer"


func get_interact_icon() -> String:
	return "open"


func get_interact_reach() -> float:
	return maxf(CoopRules.revive_range() - 70.0, 10.0)


func interact(_player: Node) -> void:
	if coop != null:
		coop.begin_revive()


func release_interact(_player: Node = null) -> void:
	if coop != null:
		coop.end_revive()


func is_searching() -> bool:
	return coop != null and coop.is_reviving()


func _draw_tag() -> void:
	var font := ThemeDB.fallback_font
	var txt := peer_name
	var col := NAME_COLOR
	if partner_status != CoopRules.Status.ALIVE:
		txt += " — " + CoopRules.status_text(partner_status)
		col = Color(1.0, 0.5, 0.45) if partner_status == CoopRules.Status.DOWNED else Color(0.8, 0.82, 0.88)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var at := Vector2(-w * 0.5, 0.0)
	_tag.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0.05, 0.07, 0.14))
	_tag.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	if net_downed:
		var c := Vector2(0.0, -24.0)
		_tag.draw_circle(c, 16.0, Color(0.05, 0.07, 0.13, 0.85))
		_tag.draw_arc(c, 12.0, 0.0, TAU, 32, Color(1, 1, 1, 0.2), 4.0, true)
		if revive_ratio > 0.0:
			_tag.draw_arc(c, 12.0, -PI * 0.5, -PI * 0.5 + TAU * revive_ratio, 32, Color(0.45, 1.0, 0.55), 4.0, true)
		# Croix de soin.
		_tag.draw_rect(Rect2(c + Vector2(-2.5, -7), Vector2(5, 14)), Color(1.0, 0.45, 0.4))
		_tag.draw_rect(Rect2(c + Vector2(-7, -2.5), Vector2(14, 5)), Color(1.0, 0.45, 0.4))
