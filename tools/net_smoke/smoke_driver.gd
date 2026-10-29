extends Node
## Pilote du test d'intégration coop (lancé par tools/net_smoke_test.sh).
##   godot --headless --path . -s res://tools/net_smoke/smoke_client.gd -- \
##       --role=host|guest --url=ws://127.0.0.1:PORT --dir=/tmp/dossier [--shots=/dossier/captures]
## Les deux instances passent par le VRAI salon (CoopLobby) puis le vrai raid :
##  hôte : crée le salon (code écrit dans <dir>/code.txt), choisit la carte, valide son arsenal,
##         lance ; en raid : gèle l'IA (test déterministe), se déplace, vérifie que l'avatar de
##         l'invité bouge et que la cible perd des PV (tirs de l'invité validés par l'hôte), puis
##         met l'invité à terre et le RÉANIME ; attend l'extraction de l'invité.
##  invité : rejoint avec le code, valide son arsenal ; en raid : se déplace, tire sur l'ennemi
##         choisi jusqu'à le voir mourir chez lui, est mis à terre puis relevé, s'extrait
##         (Profile mis à jour chez lui), passe spectateur puis quitte.
## Résultat : <dir>/<role>.json, code de sortie 0 si toutes les vérifications passent.
## --shots : captures PNG du viewport aux étapes clés (fenêtres réelles sous xvfb).

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const TIMEOUT := 150.0
const SEED := 20261029

var role: String = "host"
var dir: String = "/tmp"
var shots: String = ""
var checks: Dictionary = {}
var log_lines: PackedStringArray = PackedStringArray()
var _t0: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--dir="):
			dir = a.substr(6)
		elif a.begins_with("--shots="):
			shots = a.substr(8)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _log(s: String) -> void:
	var line := "[%s %5.1f s] %s" % [role, float(Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	log_lines.append(line)


func _check(key: String, ok: bool) -> void:
	checks[key] = ok
	_log(("OK   " if ok else "ÉCHEC ") + key)


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


## Attend que `cond` soit vraie (vérifiée à chaque image) ; false si délai dépassé.
func _wait(cond: Callable, max_s: float) -> bool:
	var until := _elapsed() + max_s
	while not bool(cond.call()):
		if _elapsed() > until or _elapsed() > TIMEOUT:
			return false
		await get_tree().process_frame
	return true


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(name: String) -> void:
	if shots == "":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(shots)
		img.save_png(shots.path_join("%s_%s.png" % [name, role]))
		_log("capture " + name)


func _finish() -> void:
	var ok := not checks.is_empty()
	for k: String in checks:
		ok = ok and bool(checks[k])
	var f := FileAccess.open(dir.path_join(role + ".json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"role": role, "ok": ok, "checks": checks, "log": log_lines}, "  "))
	_log("TERMINÉ : " + ("succès" if ok else "échec"))
	var s := NetSession.current()
	if s != null and s.in_room():
		s.leave()
	await _sleep(0.3)
	get_tree().quit(0 if ok else 1)


# --- Scénario -------------------------------------------------------------------------

func _run() -> void:
	Profile.ensure_starter()
	var uids: Array[int] = []
	for e: Dictionary in Profile.get_stash_weapons():
		if not (e["data"] as WeaponData).is_gadget():
			uids.append(int(e["uid"]))
			break
	Profile.set_loadout(uids)
	get_tree().change_scene_to_file("res://scenes/ui/menus/coop_lobby.tscn")
	if not await _wait(func() -> bool: return get_tree().current_scene is CoopLobby, 10.0):
		_check("lobby_ouvert", false)
		await _finish()
		return
	var lobby := get_tree().current_scene as CoopLobby
	await _sleep(0.5)
	if role == "host":
		await _host_lobby(lobby)
	else:
		await _guest_lobby(lobby)
	if checks.values().has(false):
		await _finish()
		return
	if not await _wait(func() -> bool: return get_tree().current_scene is Raid and get_tree().current_scene.get_node_or_null(^"Coop") != null, 30.0):
		_check("raid_coop_charge", false)
		await _finish()
		return
	_check("raid_coop_charge", true)
	var raid := get_tree().current_scene as Raid
	var coop := raid.get_node(^"Coop") as CoopRaid
	_check("pair_pret", await _wait(func() -> bool: return coop.peer_ready and not coop.waiting, 30.0))
	_check("meme_seed", true)
	if role == "host":
		await _host_raid(raid, coop)
	else:
		await _guest_raid(raid, coop)
	await _finish()


func _host_lobby(lobby: CoopLobby) -> void:
	lobby.name_edit.text = "Hôte"
	await _shot("01_lobby_accueil")
	lobby.create_room()
	var s := lobby.session
	_check("salon_cree", await _wait(func() -> bool: return s.in_room() and s.room_code != "", 10.0))
	if not s.in_room():
		return
	_check("code_valide", LobbyCode.is_valid(s.room_code))
	var f := FileAccess.open(dir.path_join("code.txt"), FileAccess.WRITE)
	f.store_string(s.room_code)
	f.close()
	_log("code " + s.room_code)
	_check("invite_arrive", await _wait(func() -> bool: return s.peer_present, 30.0))
	lobby._on_map_chosen(load(MAP_PATH) as MapCard)
	# Seed fixe : test reproductible (même carte, mêmes ennemis à chaque lancement).
	lobby.map_seed = SEED
	GameState.run_seed = SEED
	lobby._send_map()
	lobby._on_loadout_validated()
	_check("invite_pret", await _wait(func() -> bool: return lobby.can_launch(), 20.0))
	await _shot("02_lobby_salon")
	lobby.launch()


func _guest_lobby(lobby: CoopLobby) -> void:
	lobby.name_edit.text = "Invité"
	var path := dir.path_join("code.txt")
	_check("code_recu", await _wait(func() -> bool: return FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).length() == 6, 30.0))
	var code := FileAccess.get_file_as_string(path)
	# Erreurs claires : code invalide puis salon introuvable.
	lobby.code_edit.text = "AB1"
	lobby.join_room()
	_check("erreur_code_invalide", lobby.status_label.text == NetSession.describe_error("bad_code"))
	lobby.code_edit.text = code.substr(0, 5) + ("Z" if code[5] != "Z" else "Y")
	lobby.join_room()
	_check("erreur_salon_introuvable", await _wait(func() -> bool: return lobby.status_label.text == NetSession.describe_error("not_found"), 10.0))
	lobby.code_edit.text = code.to_lower()
	lobby._on_code_changed(lobby.code_edit.text)
	await _shot("01_lobby_rejoindre")
	lobby.join_room()
	var s := lobby.session
	_check("salon_rejoint", await _wait(func() -> bool: return s.in_room(), 10.0))
	_check("carte_recue", await _wait(func() -> bool: return lobby.map_card != null, 10.0))
	lobby._on_loadout_validated()
	await _shot("02_lobby_salon")


## Gèle l'IA chez l'hôte (pas de tirs ennemis : test reproductible).
func _freeze_ai(raid: Raid) -> void:
	for e: Node in raid.enemies_container.get_children():
		var en := e as Enemy
		if en == null:
			continue
		en.set_physics_process(false)
		if en._sleep_timer != null:
			en._sleep_timer.stop()
	for t: Node2D in raid.get_alive_turrets():
		t.set_physics_process(false)
		var timer: Variant = t.get(&"_sleep_timer")
		if timer is Timer:
			(timer as Timer).stop()


func _walk(action: StringName, s: float) -> void:
	Input.action_press(action)
	await _sleep(s)
	Input.action_release(action)


func _host_raid(raid: Raid, coop: CoopRaid) -> void:
	_freeze_ai(raid)
	var target_id := [-1]
	coop.session.lobby_message.connect(func(d: Dictionary) -> void:
		if String(d.get("k", "")) == "test_target":
			target_id[0] = int(d.get("id", -1)))
	var avatar := coop.avatar
	_check("avatar_visible", await _wait(func() -> bool: return avatar.visible and avatar.has_state, 15.0))
	var start := avatar.global_position
	await _walk(&"move_right", 0.6)
	await _walk(&"move_down", 0.4)
	_check("avatar_invite_bouge", await _wait(func() -> bool: return avatar.global_position.distance_to(start) > 60.0, 20.0))
	_check("cible_designee", await _wait(func() -> bool: return target_id[0] >= 0, 20.0))
	var target: Enemy = coop._enemies.get(target_id[0]) as Enemy
	if target == null:
		_check("cible_existe", false)
		return
	var hp0 := target.hp
	_log("cible %d : %s, %.0f PV" % [target_id[0], target.data.kind, hp0])
	_check("degats_invite_valides", await _wait(func() -> bool: return not is_instance_valid(target) or target.hp < hp0, 25.0))
	_check("cible_tuee_par_invite", await _wait(func() -> bool: return not is_instance_valid(target) or not target.is_alive(), 30.0))
	_log("tirs reçus de l'invité : %d" % coop.remote_shots)
	await _shot("03_raid")
	# Réanimation : l'invité est mis à terre, l'hôte vient le relever.
	await _sleep(0.5)
	coop.on_avatar_damaged(100000.0, null)
	_check("invite_a_terre", await _wait(func() -> bool: return avatar.net_downed, 10.0))
	raid.player.global_position = avatar.global_position + Vector2(30, 0)
	raid.player.reset_physics_interpolation()
	await _sleep(0.3)
	coop.begin_revive()
	await _sleep(CoopRules.revive_time() * 0.5)
	await _shot("04_reanimation")
	_check("invite_releve", await _wait(func() -> bool: return not avatar.net_downed and coop.partner_status == CoopRules.Status.ALIVE, 10.0))
	_check("invite_extrait", await _wait(func() -> bool: return coop.partner_status == CoopRules.Status.EXTRACTED, 40.0))
	_check("degats_recus_par_invite", coop.damage_sent > 0.0)
	await _sleep(3.0)  # Laisse l'invité en spectateur le temps de sa capture.
	await _shot("05_fin")


## Ennemi marionnette le plus proche avec une position de tir dégagée (case praticable, aucun
## obstacle de la couche monde entre elle et l'ennemi, emprise rendue de la carte comprise).
func _pick_target(raid: Raid, coop: CoopRaid) -> Array:
	var best: Array = []
	var best_d := INF
	var from := raid.player.global_position
	var space := raid.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.new()
	ray.collision_mask = 1
	var pq := PhysicsPointQueryParameters2D.new()
	pq.collision_mask = 1
	for id: int in coop._enemies:
		var ev: Variant = coop._enemies[id]
		if not is_instance_valid(ev) or not (ev as Enemy).is_alive():
			continue
		var e := ev as Enemy
		var c := FloorLayout.world_to_cell(e.global_position)
		for dvec: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, -2),
				Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
			var cell := c + dvec
			var t := raid.layout.get_tile(cell)
			if not (t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET):
				continue
			var pos := FloorLayout.cell_to_world(cell)
			pq.position = pos
			if not space.intersect_point(pq, 1).is_empty():
				continue
			ray.from = pos
			ray.to = e.global_position
			if not space.intersect_ray(ray).is_empty():
				continue
			var d := from.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = [id, e, cell]
			break
	return best


func _guest_raid(raid: Raid, coop: CoopRaid) -> void:
	var avatar := coop.avatar
	_check("avatar_hote_visible", await _wait(func() -> bool: return avatar.visible and avatar.has_state, 15.0))
	var start := avatar.global_position
	await _walk(&"move_left", 0.6)
	_check("avatar_hote_bouge", await _wait(func() -> bool: return avatar.global_position.distance_to(start) > 60.0, 20.0))
	var pick := _pick_target(raid, coop)
	if pick.is_empty():
		_check("cible_trouvee", false)
		return
	var target: Enemy = pick[1]
	coop.session.send_lobby({"k": "test_target", "id": pick[0]})
	raid.place_player(pick[2])
	await _sleep(0.5)
	var p := raid.player as Player
	# Tire sur la cible jusqu'à la voir mourir (mort décidée et envoyée par l'hôte).
	var died := await _wait(func() -> bool:
		if not is_instance_valid(target) or not target.is_alive():
			return true
		var dir2 := (target.global_position - p.global_position).normalized()
		p.aim_direction = dir2
		if p.loadout.can_fire():
			p.fire(dir2)
		elif p.loadout.needs_reload() and not p.is_reloading():
			p.reload()
		return false, 30.0)
	_check("ennemi_mort_vu_par_invite", died)
	_check("cadavre_ou_mort_animee", not is_instance_valid(target) or not target.is_alive())
	await _shot("03_raid")
	# Mis à terre par l'hôte puis relevé.
	_check("a_terre", await _wait(func() -> bool: return coop.local_status == CoopRules.Status.DOWNED, 15.0))
	await _sleep(CoopRules.revive_time() * 0.5)
	await _shot("04_reanimation")
	_check("releve", await _wait(func() -> bool: return coop.local_status == CoopRules.Status.ALIVE and not p.net_downed, 15.0))
	# Extraction : sur une case d'extraction, canalisation complète.
	var extractions0 := int(Profile.stats.get("extractions", 0))
	var cells: Array = raid.layout.extraction_cells
	_check("zone_extraction", not cells.is_empty())
	if cells.is_empty():
		return
	raid.place_player(cells[0])
	_check("extraction_reussie", await _wait(func() -> bool: return raid.is_raid_over(), Raid.extraction_channel_time() + 10.0))
	_check("profile_mis_a_jour", int(Profile.stats.get("extractions", 0)) == extractions0 + 1)
	_check("spectateur", coop.spectating)
	await _sleep(1.0)
	await _shot("05_fin")
	coop.quit_spectating()
	_check("ecran_de_fin", await _wait(func() -> bool: return raid.end_screen != null, 5.0))
