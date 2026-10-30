extends GutTest
## Tests du coop en ligne (scripts/net) : codes de salon, protocole binaire (quantification,
## sérialisation, paquets tronqués), interpolation, règles (à terre, réanimation, fin de raid,
## déconnexions), crochets inactifs en solo, butin déterministe des deux côtés.


func after_each() -> void:
	NetHooks.reset()


# --- Codes de salon -------------------------------------------------------------------

func test_lobby_code_normalize_and_validate() -> void:
	assert_eq(LobbyCode.normalize(" ab-c d2 3 "), "ABCD23")
	assert_true(LobbyCode.is_valid("ABCD23"))
	assert_false(LobbyCode.is_valid("ABCD2"), "trop court")
	assert_false(LobbyCode.is_valid("ABCDI3"), "I exclu (ambigu)")
	assert_false(LobbyCode.is_valid("ABCD03"), "0 exclu (ambigu)")
	assert_false(LobbyCode.is_valid("abcd23"), "minuscules non normalisées")
	assert_eq(LobbyCode.pretty("ABCD23"), "ABC D23")


func test_lobby_code_generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i: int in 300:
		var c := LobbyCode.generate(rng)
		assert_true(LobbyCode.is_valid(c), c)
		seen[c] = true
	assert_gt(seen.size(), 290, "codes quasi tous différents")


func test_alphabet_matches_server() -> void:
	# Constantes du protocole dans le cœur commun aux relais Node et Cloudflare.
	var js := FileAccess.get_file_as_string("res://server/relay_core.js")
	if js.is_empty():
		pass_test("server/relay_core.js absent de l'export")
		return
	assert_true(js.contains("const CODE_ALPHABET = '%s'" % LobbyCode.ALPHABET), "même alphabet que le serveur")
	assert_true(js.contains("const PROTOCOL_VERSION = %d;" % NetProtocol.VERSION), "même version de protocole que le serveur")


# --- Quantification -------------------------------------------------------------------

func test_quantization() -> void:
	assert_eq(NetProtocol.q_pos(123.4), 123)
	assert_eq(NetProtocol.q_pos(-99999.0), -32768, "borné")
	assert_eq(NetProtocol.q_pos(99999.0), 32767, "borné")
	for a: float in [0.0, 0.5, 1.7, PI, -2.2, 6.0]:
		var d8 := absf(angle_difference(a, NetProtocol.dq_angle8(NetProtocol.q_angle8(a))))
		assert_lt(d8, TAU / 256.0, "angle 8 bits")
		var d16 := absf(angle_difference(a, NetProtocol.dq_angle16(NetProtocol.q_angle16(a))))
		assert_lt(d16, TAU / 65536.0 * 1.01, "angle 16 bits")
	assert_eq(NetProtocol.q_ratio(1.2), 255)
	assert_eq(NetProtocol.q_ratio(-1.0), 0)
	assert_almost_eq(NetProtocol.dq_ratio(NetProtocol.q_ratio(0.5)), 0.5, 0.003)


# --- Sérialisation ----------------------------------------------------------------------

func _state() -> NetProtocol.PlayerState:
	var s := NetProtocol.PlayerState.new()
	s.time_ms = 123456789
	s.floor_index = -1
	s.position = Vector2(1520.6, 840.2)
	s.velocity = Vector2(-250.0, 12.0)
	s.aim = Vector2.from_angle(2.0)
	s.flags = NetProtocol.F_MOVING | NetProtocol.F_DOWNED | NetProtocol.F_FIRED
	s.hp_ratio = 0.42
	s.slot = 2
	return s


func test_state_roundtrip_and_size() -> void:
	var w := NetProtocol.Writer.new()
	NetProtocol.write_state(w, _state())
	var bytes := w.bytes()
	assert_eq(bytes.size(), 3 + NetProtocol.STATE_BYTES, "état = 20 octets en tout")
	var r := NetProtocol.Reader.new()
	r.reset(bytes)
	assert_eq(r.next_msg(), NetProtocol.Msg.STATE)
	var s := NetProtocol.PlayerState.new()
	NetProtocol.read_state(r, s)
	assert_true(r.ok)
	assert_eq(s.time_ms, 123456789)
	assert_eq(s.floor_index, -1)
	assert_eq(s.position, Vector2(1521, 840), "position quantifiée au pixel")
	assert_eq(s.velocity, Vector2(-250, 12))
	assert_lt(absf(angle_difference(s.aim.angle(), 2.0)), 0.03)
	assert_true(s.has(NetProtocol.F_DOWNED))
	assert_true(s.has(NetProtocol.F_FIRED))
	assert_false(s.has(NetProtocol.F_DEAD))
	assert_almost_eq(s.hp_ratio, 0.42, 0.004)
	assert_eq(s.slot, 2)
	assert_eq(r.next_msg(), 0, "fin du paquet")


func test_several_messages_per_packet_and_skip() -> void:
	var w := NetProtocol.Writer.new()
	NetProtocol.write_fire(w, "smg_mp5", Vector2(10, 20), Vector2.DOWN, 22.0, true)
	w.begin(NetProtocol.Msg.DOOR)
	w.i16(5)
	w.i16(-3)
	w.u8(FloorLayout.DoorState.OPEN)
	w.end()
	w.begin(NetProtocol.Msg.CONTAINER)
	w.u8(NetProtocol.ContainerOp.TAKEN)
	w.text("0:4:7")
	w.text("gold_nugget")
	w.u16(3)
	w.end()
	var r := NetProtocol.Reader.new()
	r.reset(w.bytes())
	assert_eq(r.next_msg(), NetProtocol.Msg.FIRE)
	var f := NetProtocol.read_fire(r)
	assert_eq(f["weapon"], "smg_mp5")
	assert_eq(f["origin"], Vector2(10, 20))
	assert_lt((f["dir"] as Vector2).distance_to(Vector2.DOWN), 0.001)
	assert_eq(f["height"], 22.0)
	assert_true(f["homing"])
	# Message non lu : sauté grâce à sa longueur.
	assert_eq(r.next_msg(), NetProtocol.Msg.DOOR)
	assert_eq(r.next_msg(), NetProtocol.Msg.CONTAINER)
	assert_eq(r.u8(), NetProtocol.ContainerOp.TAKEN)
	assert_eq(r.text(), "0:4:7")
	assert_eq(r.text(), "gold_nugget")
	assert_eq(r.u16(), 3)
	assert_eq(r.next_msg(), 0)
	assert_true(r.ok)


func test_truncated_packet_is_rejected() -> void:
	var w := NetProtocol.Writer.new()
	NetProtocol.write_state(w, _state())
	var bytes := w.bytes().slice(0, 10)
	var r := NetProtocol.Reader.new()
	r.reset(bytes)
	assert_eq(r.next_msg(), 0, "message tronqué ignoré")
	assert_false(r.ok)
	# Lecture au-delà d'un message : valeurs nulles, ok = faux, pas de plantage.
	var w2 := NetProtocol.Writer.new()
	w2.begin(NetProtocol.Msg.DAMAGE)
	w2.u8(1)
	w2.end()
	r.reset(w2.bytes())
	assert_eq(r.next_msg(), NetProtocol.Msg.DAMAGE)
	assert_eq(r.f32(), 0.0)
	assert_false(r.ok)


func test_enemy_snapshot_size_and_budget() -> void:
	var w := NetProtocol.Writer.new()
	NetProtocol.begin_enemy_snap(w, 1000, 0, 30)
	for i: int in 30:
		NetProtocol.write_enemy(w, i, Vector2(i * 64, 300), Vector2.LEFT, NetProtocol.EF_MOVING, 0.5, 0.2)
	w.end()
	var size := w.bytes().size()
	assert_eq(size, 3 + 6 + 30 * NetProtocol.ENEMY_ENTRY_BYTES, "10 octets par ennemi")
	var rate_state := Balance.get_float("net", "state_rate", 20.0)
	var rate_enemy := Balance.get_float("net", "enemy_rate", 15.0)
	var bytes_per_s := rate_state * (3 + NetProtocol.STATE_BYTES) + rate_enemy * size
	assert_lt(bytes_per_s, 8.0 * 1024.0, "moins de 8 ko/s avec 30 ennemis proches")
	assert_between(rate_state, 15.0, 20.0, "15 à 20 envois d'état par seconde")


func test_fx_methods_table() -> void:
	assert_eq(NetProtocol.fx_method(NetProtocol.fx_index(&"play_attack_windup")), &"play_attack_windup")
	assert_eq(NetProtocol.fx_index(&"methode_inconnue"), -1)
	assert_eq(NetProtocol.fx_method(999), &"")
	assert_true(NetProtocol.compatible({"gv": NetProtocol.GAME_VERSION}))
	assert_false(NetProtocol.compatible({"gv": NetProtocol.GAME_VERSION + 1}))
	assert_false(NetProtocol.compatible({}))


# --- Interpolation ----------------------------------------------------------------------

func test_snapshot_buffer_interpolates_and_extrapolates() -> void:
	var b := SnapshotBuffer.new()
	b.extrapolate_max = 0.1
	var out := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	b.push(1000, Vector2(0, 0), Vector2(100, 0), Vector2.RIGHT)
	b.push(1050, Vector2(5, 0), Vector2(100, 0), Vector2.RIGHT)
	b.push(1100, Vector2(10, 0), Vector2(100, 0), Vector2.DOWN)
	assert_eq(b.sample(1025.0, out), Vector2(2.5, 0), "milieu")
	assert_eq(b.sample(900.0, out), Vector2(0, 0), "avant le premier : premier")
	# Au-delà du dernier : extrapolation par la vitesse, bornée.
	assert_almost_eq(b.sample(1150.0, out).x, 15.0, 0.01)
	assert_almost_eq(b.sample(5000.0, out).x, 20.0, 0.01, "bornée à extrapolate_max")
	assert_false(b.push(1080, Vector2(99, 99), Vector2.ZERO, Vector2.RIGHT), "échantillon en retard ignoré")
	assert_eq(b.latest_position(), Vector2(10, 0))
	assert_true(b.push(1150, Vector2(3000, 0), Vector2.ZERO, Vector2.RIGHT), "saut = téléportation")
	assert_eq(b.count, 1)


func test_clock_sync_keeps_lowest_latency() -> void:
	var c := SnapshotBuffer.ClockSync.new()
	c.observe(1000, 5100)  # latence 100
	c.observe(1050, 5130)  # latence 80 : meilleure
	assert_eq(c.offset, 4080.0)
	c.observe(1100, 5300)  # pic de latence : à peine relâché
	assert_lt(c.offset, 4082.0)
	assert_almost_eq(c.remote_now(6080), 2000.0, 1.0)


# --- Règles du coop -------------------------------------------------------------------

func test_downed_and_revive_rules() -> void:
	assert_true(CoopRules.should_go_down(CoopRules.Status.ALIVE, true))
	assert_false(CoopRules.should_go_down(CoopRules.Status.ALIVE, false), "coéquipier déconnecté : mort directe")
	assert_false(CoopRules.should_go_down(CoopRules.Status.DOWNED, true), "les deux à terre : mort")
	assert_false(CoopRules.should_go_down(CoopRules.Status.EXTRACTED, true))
	assert_eq(CoopRules.step_downed(10.0, 1.0, false), 9.0)
	assert_eq(CoopRules.step_downed(10.0, 1.0, true), 10.0, "suspendu pendant la réanimation")
	assert_eq(CoopRules.step_downed(0.5, 1.0, false), 0.0)
	var t := CoopRules.revive_time()
	var p := CoopRules.step_revive(0.0, t * 0.5, 20.0, true, true)
	assert_almost_eq(p, 0.5, 0.001)
	assert_eq(CoopRules.step_revive(p, t, 20.0, true, true), 1.0)
	assert_eq(CoopRules.step_revive(p, 0.1, CoopRules.revive_range() + 1.0, true, true), -1.0, "trop loin")
	assert_eq(CoopRules.step_revive(p, 0.1, 10.0, false, true), -1.0, "réanimateur hors d'état")
	assert_eq(CoopRules.step_revive(p, 0.1, 10.0, true, false), -1.0, "cible plus à terre")


func test_end_of_raid_rules() -> void:
	assert_true(CoopRules.should_spectate(CoopRules.Status.ALIVE, true, false))
	assert_true(CoopRules.should_spectate(CoopRules.Status.DOWNED, true, false))
	assert_false(CoopRules.should_spectate(CoopRules.Status.EXTRACTED, true, false), "les deux ont fini")
	assert_false(CoopRules.should_spectate(CoopRules.Status.ALIVE, false, false), "coéquipier déconnecté")
	assert_false(CoopRules.should_spectate(CoopRules.Status.ALIVE, true, true), "abandon : écran de fin direct")
	assert_eq(CoopRules.guest_outcome("host_left"), &"keep_arsenal")
	assert_eq(CoopRules.guest_outcome("host_timeout"), &"keep_arsenal")
	assert_eq(CoopRules.guest_outcome("not_found"), &"keep_arsenal")
	assert_eq(CoopRules.guest_outcome("bad_token"), &"death", "absent plus de 20 s : mort")
	assert_eq(CoopRules.guest_outcome("unreachable"), &"death")
	assert_gt(CoopRules.coop_hp_mult(), 1.0, "ennemis plus solides à deux")


class FakeProfile extends Node:
	var raid_weapon_ids: Array[StringName] = [&"pistol_p9", &"smg_mp5"]
	var raid_in_progress: bool = true
	var added: Array[StringName] = []
	var saved: bool = false

	func add_weapon(id: StringName) -> int:
		added.append(id)
		return added.size()

	func ensure_starter() -> bool:
		return false

	func save() -> void:
		saved = true


func test_host_lost_keeps_arsenal_loses_loot() -> void:
	var fp := FakeProfile.new()
	var bag := Inventory.from_balance()
	var item := LootDB.get_item(&"gold_nugget")
	if item != null:
		bag.add_item(item, 2)
	var res := CoopRules.apply_host_lost(fp, bag)
	assert_eq(fp.added, [&"pistol_p9", &"smg_mp5"] as Array[StringName], "arsenal emporté rendu à la réserve")
	assert_true(fp.raid_weapon_ids.is_empty())
	assert_false(fp.raid_in_progress)
	assert_true(fp.saved)
	assert_eq((res["kept_weapons"] as Array).size(), 2)
	if item != null:
		assert_eq(int(res["lost_items"]), 2, "butin du raid compté comme perdu")
	fp.free()


# --- Crochets -------------------------------------------------------------------------

func test_hooks_inactive_in_solo() -> void:
	assert_false(NetHooks.active)
	assert_false(NetHooks.blocks_local_damage())
	assert_false(NetHooks.intercept_stairs({"target_floor": 1, "target_cell": Vector2i.ZERO}))
	assert_false(NetHooks.defer_end_screen(true, {}))
	assert_false(NetHooks.player_down(null))
	assert_eq(NetHooks.view_position(Vector2(4, 5)), Vector2(4, 5))
	assert_true(NetHooks.container_can_use(null))
	var raid := Node.new()
	add_child_autofree(raid)
	NetHooks.attach_raid(raid)
	assert_eq(raid.get_child_count(), 0, "pas de salon : aucun CoopRaid attaché")
	assert_null(NetSession.current(), "aucune session créée en solo")


func test_enemy_target_picks_nearest_targetable() -> void:
	var e := Node2D.new()
	var a := Node2D.new()
	var b := Node2D.new()
	add_child_autofree(e)
	add_child_autofree(a)
	add_child_autofree(b)
	a.global_position = Vector2(100, 0)
	b.global_position = Vector2(300, 0)
	NetHooks.targets.assign([a, b])
	assert_eq(NetHooks.enemy_target(e, null), a)
	# Préférence pour la cible actuelle (pas de va-et-vient) tant que l'écart est faible.
	b.global_position = Vector2(110, 0)
	assert_eq(NetHooks.enemy_target(e, b), b)
	a.set_meta(&"coop_gone", true)
	b.visible = false
	assert_null(NetHooks.enemy_target(e, a), "extrait / caché : plus ciblable")


func test_guest_mode_blocks_local_damage_except_remote() -> void:
	NetHooks.active = true
	NetHooks.guest_mode = true
	assert_true(NetHooks.blocks_local_damage())
	NetHooks.applying_remote = true
	assert_false(NetHooks.blocks_local_damage(), "dégâts envoyés par l'hôte appliqués")


func test_server_url_override() -> void:
	OS.set_environment("RAIDERSGO_NET_URL", "ws://exemple:1234")
	assert_eq(NetSession.server_url(), "ws://exemple:1234")
	OS.unset_environment("RAIDERSGO_NET_URL")
	var u := NetSession.server_url()
	assert_true(u.begins_with("ws://") or u.begins_with("wss://"), u)
	for code: String in ["unreachable", "version", "bad_code", "not_found", "full", "game_version"]:
		assert_ne(NetSession.describe_error(code), "", code)


# --- Butin déterministe ---------------------------------------------------------------

func test_container_same_content_on_both_sides() -> void:
	var a := LootContainer.create(&"chest", Vector2(100, 100))
	var b := LootContainer.create(&"chest", Vector2(100, 100))
	for c: LootContainer in [a, b]:
		c.loot_seed = 424242
		c.floor_index = 0
		c.difficulty = 2
		c.room_type = &"loot"
		c.persist_key = ""
		add_child_autofree(c)
	a.force_open()
	b.net_open_silently()
	assert_eq(b.state, a.state, "même état")
	assert_eq(a.entries.size(), b.entries.size(), "même nombre d'objets")
	for i: int in a.entries.size():
		assert_eq((a.entries[i]["item"] as ItemData).id, (b.entries[i]["item"] as ItemData).id)
		assert_eq(int(a.entries[i]["count"]), int(b.entries[i]["count"]))
	if not b.entries.is_empty():
		var it := b.entries[0]["item"] as ItemData
		var n := int(b.entries[0]["count"])
		var before := b.entries.size()
		b.net_remove(it.id, n)
		assert_true(b.entries.size() == before - 1 or b.is_emptied(), "objet pris par le coéquipier retiré")
	assert_eq(CoopRaid.container_key(a), "p:0:100:100", "clef réseau par position sans clef de persistance")
	a.persist_key = "0:3:4"
	assert_eq(CoopRaid.container_key(a), "0:3:4")
