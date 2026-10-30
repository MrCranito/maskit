extends GutTest
## Sauvegarde cloud (CloudSync) : décision locale/cloud, métadonnées de version dans la
## sauvegarde, charge utile envoyée, restauration d'une sauvegarde distante (SaveManager.replace_data
## → Profile / BattlePass rechargés), résumé pour l'écran de conflit. Aucun réseau (headless :
## CloudSync est désactivé, les appels HTTP ne partent jamais). Sauvegarde isolée.

const CS := preload("res://scripts/net/cloud_sync.gd")

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_pass: Dictionary = {}


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	_saved_pass = BattlePassSystem.get_instance().to_dict()


func after_each() -> void:
	BattlePassSystem.get_instance().from_dict(_saved_pass)
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_data
	SaveManager.save()


func test_disabled_in_headless() -> void:
	assert_false(CloudSync.enabled(), "pas de réseau en headless / tests")
	assert_eq(CloudSync.status, CS.STATUS_DISABLED)


func test_decide_first_sync() -> void:
	# Appareil neuf, compte neuf : rien sur le serveur → on pousse ce qu'on a.
	assert_eq(CS.decide(0, false, true, false, 0), CS.Action.PUSH)
	assert_eq(CS.decide(0, false, false, false, 0), CS.Action.NOTHING)
	# Jamais synchronisé avec ce compte mais le serveur en a une : le cloud fait foi…
	assert_eq(CS.decide(0, false, true, true, 5), CS.Action.PULL)
	# …sauf si l'appareil a vraiment progressé (changement de compte) : le joueur tranche.
	assert_eq(CS.decide(0, true, true, true, 5), CS.Action.CONFLICT)


func test_decide_same_version() -> void:
	assert_eq(CS.decide(5, false, true, true, 5), CS.Action.NOTHING)
	assert_eq(CS.decide(5, true, true, true, 5), CS.Action.PUSH)


func test_decide_remote_newer() -> void:
	# Joué ailleurs, rien de nouveau ici → on prend le cloud sans rien demander.
	assert_eq(CS.decide(3, false, true, true, 7), CS.Action.PULL)
	# Joué ailleurs ET ici → le joueur tranche.
	assert_eq(CS.decide(3, true, true, true, 7), CS.Action.CONFLICT)


func test_decide_local_newer() -> void:
	assert_eq(CS.decide(9, false, true, true, 4), CS.Action.PUSH)


func test_payload_strips_meta() -> void:
	var data := {"profile": {"gems": 3}, "_cloud": {"version": 4, "dirty": true}, "settings": {"music_volume": 0.5}}
	var p := CS.payload_of(data)
	assert_false(p.has("_cloud"))
	assert_true(p.has("profile") and p.has("settings"))
	assert_true(data.has("_cloud"), "l'original n'est pas modifié")
	assert_true(CS.has_content(data))
	assert_false(CS.has_content({"settings": {}}))


func test_meta_version_and_dirty() -> void:
	SaveManager.data["_cloud"] = {"version": 12, "dirty": true}
	assert_eq(CloudSync.local_version(), 12)
	assert_true(CloudSync.is_dirty())
	SaveManager.data.erase("_cloud")
	assert_eq(CloudSync.local_version(), 0)
	assert_false(CloudSync.is_dirty())


func test_replace_data_reloads_profile_and_pass() -> void:
	var remote := {
		"profile": {"gems": 77, "gold": 1234, "raider_xp": 0,
			"weapons": [{"uid": 1, "id": String(WeaponCatalog.STARTER_ID)}], "loadout": [1], "next_uid": 2},
		"battle_pass": {"xp": 0, "premium": false},
		"settings": {"music_volume": 0.33},
		"_cloud": {"version": 3, "dirty": false},
	}
	SaveManager.replace_data(remote)
	assert_eq(Profile.gems, 77, "profil rechargé depuis la sauvegarde restaurée")
	assert_eq(Profile.gold, 1234)
	assert_eq(float(MenuKit.get_setting(&"music_volume", 0.0)), 0.33)
	assert_eq(CloudSync.local_version(), 3)
	assert_true(FileAccess.file_exists(SaveManager.SAVE_PATH))
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	assert_true(on_disk is Dictionary and (on_disk as Dictionary).has("_cloud"), "métadonnées cloud écrites sur le disque")


func test_saved_signal_emitted() -> void:
	watch_signals(SaveManager)
	SaveManager.save()
	assert_signal_emitted(SaveManager, "saved")


func test_describe_save() -> void:
	var save := {"profile": {"gems": 5, "gold": 40, "raider_xp": 0, "weapons": [{}, {}, {}],
		"stats": {"raids": 9, "extractions": 4}}}
	var d := CS.describe_save(save, "2026-10-30T09:52:22.613217+00:00", "iPhone")
	assert_eq(d["gems"], 5)
	assert_eq(d["gold"], 40)
	assert_eq(d["weapons"], 3)
	assert_eq(d["raids"], 9)
	assert_eq(d["raider_level"], RaiderProgress.level_for_xp(0))
	assert_eq(d["device"], "iPhone")
	var empty := CS.describe_save({})
	assert_eq(empty["weapons"], 0)
	assert_eq(empty["gems"], 0)


func test_conflict_panel_builds() -> void:
	var p := CloudConflictPanel.new({"gems": 1, "updated_at": ""}, {"gems": 2, "updated_at": "2026-10-30T09:52:22+00:00", "device": "Pixel"})
	add_child_autofree(p)
	assert_not_null(p.keep_local_button)
	assert_not_null(p.keep_remote_button)
	assert_false(p.close_button.visible, "pas de bouton Fermer : il faut choisir")
	assert_eq(CloudConflictPanel.format_date(""), "Maintenant")
	assert_true(CloudConflictPanel.format_date("2026-10-30T09:52:22+00:00").begins_with("30/10/2026"))


func test_pkce_challenge() -> void:
	# Vecteur RFC 7636 appendix B.
	assert_eq(AccountLink.challenge_for("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
	var l := AccountLink.new()
	var c := l.new_challenge()
	assert_eq(l.code_verifier.length(), 43)
	assert_eq(c, AccountLink.challenge_for(l.code_verifier))
	assert_false(c.contains("=") or c.contains("+") or c.contains("/"))
	l.free()


func test_parse_callback() -> void:
	var q := AccountLink.parse_callback("GET /cb?code=abc%2D1&state=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
	assert_eq(q.get("code"), "abc-1")
	assert_eq(q.get("state"), "x")
	var e := AccountLink.parse_callback("GET /cb?error=access_denied&error_description=User+denied HTTP/1.1\r\n")
	assert_eq(e.get("error_description"), "User denied")
	assert_true(AccountLink.parse_callback("GET /favicon.ico HTTP/1.1\r\n").is_empty())


func test_provider_of() -> void:
	assert_eq(CS.provider_of({"identities": [{"provider": "google"}]}), "google")
	assert_eq(CS.provider_of({"identities": [], "app_metadata": {"provider": "anonymous"}}), "")
	assert_eq(CS.provider_of({}), "")


func test_has_progress() -> void:
	assert_false(CS.has_progress({"profile": {"gems": 0, "gold": 0, "weapons": [{}], "stats": {"raids": 0}}}))
	assert_true(CS.has_progress({"profile": {"gems": 0, "gold": 0, "weapons": [{}], "stats": {"raids": 1}}}))
	assert_true(CS.has_progress({"profile": {"gems": 5, "weapons": [{}]}}))


func test_status_labels() -> void:
	for s: StringName in [CS.STATUS_DISABLED, CS.STATUS_OFFLINE, CS.STATUS_SYNCING, CS.STATUS_SYNCED, CS.STATUS_CONFLICT]:
		assert_false(CS.status_label(s).is_empty())
