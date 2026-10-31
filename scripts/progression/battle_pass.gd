class_name BattlePassSystem
extends Node
## Pass de combat (autoload `BattlePass`, ce script) : XP de saison gagnée en fin de raid,
## 30 paliers, piste gratuite + piste premium achetée en gemmes. Purement cosmétique/confort :
## skins (personnage et armes), gemmes, or, objets. Sauvegardé dans SaveManager.data["battle_pass"].
##
## Accès : `BattlePass` (autoload) ou `BattlePassSystem.get_instance()` (fonctionne aussi sans
## l'autoload : le nœud est alors créé à la demande sous /root).
## Fin de raid (raid.gd) : add_raid_xp({success, value, kills?, time?}) → {xp, tier_before, tier_after}.
## Les kills et le temps survécu sont comptés ici (EventBus.raid_started / enemy_died) quand
## le résumé ne les fournit pas.

signal changed
signal xp_gained(amount: int, tier_before: int, tier_after: int)

const SAVE_KEY := "battle_pass"
const DEFAULT_SEASON := "res://data/battle_pass/season_01.tres"
const FREE := &"free"
const PREMIUM := &"premium"

static var _instance: BattlePassSystem = null

var season: BattlePassSeason = null
## XP cumulée de la saison.
var xp: int = 0
var premium: bool = false
## Récompenses récupérées : "free:5" / "premium:12" → true.
var claimed: Dictionary = {}
## Dernier gain (affiché par les écrans) : {xp, tier_before, tier_after}.
var last_gain: Dictionary = {}

var _loaded: bool = false
## « Tout débloquer » (DevMode) actif : pass de développement en mémoire.
var _dev_active: bool = false
var _raid_kills: int = 0
var _raid_start_ms: int = -1


## Instance active : l'autoload /root/BattlePass s'il existe, sinon un nœud créé à la demande.
static func get_instance() -> BattlePassSystem:
	if is_instance_valid(_instance):
		return _instance
	var ml := Engine.get_main_loop() as SceneTree
	if ml != null:
		var n := ml.root.get_node_or_null(^"BattlePass") as BattlePassSystem
		if n != null:
			_instance = n
			n._ensure_loaded()
			return n
	var bp := BattlePassSystem.new()
	bp.name = "BattlePass"
	_instance = bp
	bp._ensure_loaded()
	if ml != null:
		ml.root.add_child.call_deferred(bp)
	return bp


func _enter_tree() -> void:
	if not is_instance_valid(_instance):
		_instance = self


func _ready() -> void:
	_ensure_loaded()


func _connect_bus() -> void:
	var ml := Engine.get_main_loop() as SceneTree
	var bus: Node = ml.root.get_node_or_null(^"EventBus") if ml != null else null
	if bus != null:
		if not bus.is_connected(&"raid_started", _on_raid_started):
			bus.connect(&"raid_started", _on_raid_started)
		if not bus.is_connected(&"enemy_died", _on_enemy_died):
			bus.connect(&"enemy_died", _on_enemy_died)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load()
	_connect_bus()
	if not DevMode.notifier.unlock_changed.is_connected(_on_dev_unlock_changed):
		DevMode.notifier.unlock_changed.connect(_on_dev_unlock_changed)
	if DevMode.is_all_unlocked():
		_on_dev_unlock_changed(true)


# --- Saison et paliers ------------------------------------------------------------------

func get_season() -> BattlePassSeason:
	if season == null:
		var p := str(Balance.get_value("battle_pass", "season_path", DEFAULT_SEASON))
		season = load(p) as BattlePassSeason if ResourceLoader.exists(p) else null
		if season == null:
			season = BattlePassSeason.new()
	return season


func max_tier() -> int:
	return get_season().tiers


## Palier atteint (0 = aucun, max_tier() = pass terminé).
func tier() -> int:
	var s := get_season()
	var t := 0
	var acc := 0
	while t < s.tiers:
		acc += s.xp_for_tier(t + 1)
		if xp < acc:
			break
		t += 1
	return t


## XP gagnée dans le palier en cours et XP nécessaire pour le suivant ([0, 0] si terminé).
func tier_progress() -> Vector2i:
	var t := tier()
	if t >= max_tier():
		return Vector2i(0, 0)
	var s := get_season()
	return Vector2i(xp - s.xp_total_for(t), s.xp_for_tier(t + 1))


## Ajoute de l'XP. Renvoie {xp, tier_before, tier_after, total_before, total_after} (XP cumulée de
## la saison avant/après : barres de progression de l'écran de fin).
func add_xp(amount: int) -> Dictionary:
	var before := tier()
	var total_before := xp
	var cap := get_season().xp_total_for(max_tier())
	xp = clampi(xp + maxi(amount, 0), 0, cap)
	var after := tier()
	last_gain = {"xp": maxi(amount, 0), "tier_before": before, "tier_after": after,
		"total_before": total_before, "total_after": xp}
	save()
	xp_gained.emit(maxi(amount, 0), before, after)
	return last_gain.duplicate()


# --- XP de raid ----------------------------------------------------------------------

## XP d'une fin de raid (balance.cfg [battle_pass]) : extraction réussie (base + valeur extraite)
## ou mort (un peu d'XP), + kills, + minutes survécues ; plafonnée.
## summary : {success: bool, value: int, kills: int, time: float (s)}.
static func raid_xp(summary: Dictionary) -> int:
	var x := 0.0
	for line: Dictionary in _raid_xp_lines(summary):
		x += float(line["xp"])
	return mini(roundi(x), int(Balance.get_value("battle_pass", "xp_raid_max", 1500)))


## Détail de raid_xp pour l'écran de fin : [{id, label, xp (arrondi)}] (lignes à 0 omises), plus
## une ligne « cap » négative si le plafond par raid s'applique. La somme vaut raid_xp(summary).
static func raid_xp_breakdown(summary: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sum := 0
	for line: Dictionary in _raid_xp_lines(summary):
		var v := roundi(float(line["xp"]))
		if v != 0:
			out.append({"id": line["id"], "label": line["label"], "xp": v})
			sum += v
	var total := raid_xp(summary)
	if sum != total and not out.is_empty():
		if total < sum and sum - total > out.size():
			out.append({"id": &"cap", "label": "Plafond du raid", "xp": total - sum})
		else:
			out[0]["xp"] = int(out[0]["xp"]) + total - sum   # écart d'arrondi
	return out


static func _raid_xp_lines(summary: Dictionary) -> Array[Dictionary]:
	var success := bool(summary.get("success", false))
	var kills := maxi(int(summary.get("kills", 0)), 0)
	var minutes := clampf(float(summary.get("time", 0.0)) / 60.0, 0.0, Balance.get_float("battle_pass", "xp_max_minutes", 20.0))
	var factor := 1.0 if success else Balance.get_float("battle_pass", "xp_death_factor", 0.5)
	var out: Array[Dictionary] = []
	if success:
		out.append({"id": &"extraction", "label": "Extraction", "xp": Balance.get_float("battle_pass", "xp_extraction", 250.0)})
		out.append({"id": &"loot", "label": "Butin extrait",
			"xp": maxf(float(summary.get("loot_value", summary.get("value", 0))), 0.0) * Balance.get_float("battle_pass", "xp_per_value", 0.08)})
	else:
		out.append({"id": &"death", "label": "Participation", "xp": Balance.get_float("battle_pass", "xp_death", 60.0)})
	out.append({"id": &"kills", "label": "%d élimination%s" % [kills, "s" if kills > 1 else ""],
		"xp": kills * Balance.get_float("battle_pass", "xp_per_kill", 12.0) * factor})
	out.append({"id": &"time", "label": "%d min de raid" % floori(minutes),
		"xp": minutes * Balance.get_float("battle_pass", "xp_per_minute", 15.0) * factor})
	return out


## Fin de raid (appelée par raid.gd). Complète kills / temps avec les compteurs du raid.
## Renvoie le résultat de add_xp + {kills, time (s), breakdown (raid_xp_breakdown)}.
func add_raid_xp(summary: Dictionary) -> Dictionary:
	var s := summary.duplicate()
	if not s.has("kills"):
		s["kills"] = _raid_kills
	if not s.has("time") and _raid_start_ms >= 0:
		s["time"] = (Time.get_ticks_msec() - _raid_start_ms) / 1000.0
	_raid_kills = 0
	_raid_start_ms = -1
	var r := add_xp(raid_xp(s))
	r["kills"] = int(s.get("kills", 0))
	r["time"] = float(s.get("time", 0.0))
	r["breakdown"] = raid_xp_breakdown(s)
	last_gain = r.duplicate()
	return r


func _on_raid_started(_seed: int) -> void:
	_raid_kills = 0
	_raid_start_ms = Time.get_ticks_msec()


func _on_enemy_died(_enemy: Node2D, _pos: Vector2) -> void:
	if _raid_start_ms >= 0:
		_raid_kills += 1


# --- Premium ----------------------------------------------------------------------------

static func premium_price() -> int:
	return int(Balance.get_value("battle_pass", "premium_price", 950))


## Débloque la piste premium contre des gemmes (Profile). false si déjà fait ou pas assez.
func buy_premium() -> bool:
	var p := _profile()
	if premium or p == null:
		return false
	var price := premium_price()
	if not bool(p.call("debit", &"gems", price)):
		return false
	p.call("save")
	premium = true
	save()
	return true


# --- Récompenses ------------------------------------------------------------------------

func reward(t: int, track: StringName) -> Dictionary:
	return get_season().reward(t, track)


func is_claimed(t: int, track: StringName) -> bool:
	return claimed.has("%s:%d" % [track, t])


## Récupérable : palier atteint, récompense non vide, non récupérée, premium débloqué si besoin.
func can_claim(t: int, track: StringName) -> bool:
	if t < 1 or t > tier() or is_claimed(t, track):
		return false
	if track == PREMIUM and not premium:
		return false
	return not reward(t, track).is_empty()


## Récupère une récompense (une seule fois). Renvoie true si obtenue.
func claim(t: int, track: StringName) -> bool:
	if not can_claim(t, track):
		return false
	_grant(reward(t, track))
	claimed["%s:%d" % [track, t]] = true
	save()
	return true


## Récupère tout ce qui est disponible. Renvoie le nombre de récompenses obtenues.
func claim_all() -> int:
	var n := 0
	for t: int in range(1, tier() + 1):
		for track: StringName in [FREE, PREMIUM]:
			if can_claim(t, track):
				_grant(reward(t, track))
				claimed["%s:%d" % [track, t]] = true
				n += 1
	if n > 0:
		save()
	return n


func claimable_count() -> int:
	var n := 0
	for t: int in range(1, tier() + 1):
		for track: StringName in [FREE, PREMIUM]:
			if can_claim(t, track):
				n += 1
	return n


## Ce skin s'obtient-il dans le pass ? (source « pass » ou présent dans la saison)
func is_pass_skin(id: StringName) -> bool:
	var s := SkinData.get_skin(id)
	return (s != null and s.is_pass()) or get_season().skin_ids().has(id)


## Palier et piste où l'on obtient ce skin ({tier, track}, {} si absent).
func find_skin(id: StringName) -> Dictionary:
	var s := get_season()
	for track: StringName in [FREE, PREMIUM]:
		for t: int in range(1, s.tiers + 1):
			var r := s.reward(t, track)
			if str(r.get("type", "")) == "skin" and StringName(str(r.get("id", ""))) == id:
				return {"tier": t, "track": track}
	return {}


## Libellé court d'une récompense (« 25 gemmes », « Néon violet »…).
static func reward_label(r: Dictionary) -> String:
	var n := int(r.get("amount", 1))
	match str(r.get("type", "")):
		"gems":
			return "%d gemmes" % n
		"gold":
			return "%d or" % n
		"item":
			var it := load("res://data/items/%s.tres" % str(r.get("id", ""))) as ItemData \
				if ResourceLoader.exists("res://data/items/%s.tres" % str(r.get("id", ""))) else null
			var nm: String = it.display_name if it != null else str(r.get("id", ""))
			return ("%s ×%d" % [nm, n]) if n > 1 else nm
		"skin":
			var s := SkinData.get_skin(StringName(str(r.get("id", ""))))
			return s.display_name if s != null else str(r.get("id", ""))
	return ""


func _grant(r: Dictionary) -> void:
	var p := _profile()
	if p == null:
		return
	var n := maxi(int(r.get("amount", 1)), 0)
	match str(r.get("type", "")):
		"gems":
			p.call("add_gems", n)
		"gold":
			# Or (pièces) : Profile.add_gold / Profile.gold si l'économie les fournit, sinon dollars.
			if p.has_method(&"add_gold"):
				p.call("add_gold", n)
			elif &"gold" in p:
				p.set("gold", int(p.get("gold")) + n)
				p.call("save")
			else:
				p.set("dollars", int(p.get("dollars")) + n)
				p.call("save")
		"item":
			var id := str(r.get("id", ""))
			if p.has_method(&"add_item"):
				p.call("add_item", StringName(id), n)
			else:
				var items: Dictionary = p.get("items")
				items[id] = int(items.get(id, 0)) + n
				p.call("save")
		"skin":
			var sid := StringName(str(r.get("id", "")))
			var owned: Array = p.get("skins_owned")
			if SkinData.get_skin(sid) != null and not owned.has(sid):
				owned.append(sid)
				p.call("save")


func _profile() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(^"Profile") if ml != null else null


# --- Sauvegarde --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"season": String(get_season().id), "xp": xp, "premium": premium, "claimed": claimed.keys()}


## Charge un état ; une autre saison remet le pass à zéro (les skins obtenus restent au profil).
func from_dict(d: Dictionary) -> void:
	xp = 0
	premium = false
	claimed.clear()
	if str(d.get("season", String(get_season().id))) != String(get_season().id):
		return
	xp = maxi(int(d.get("xp", 0)), 0)
	premium = bool(d.get("premium", false))
	var c: Variant = d.get("claimed", [])
	if c is Array:
		for k: Variant in c:
			claimed[str(k)] = true


func reset() -> void:
	from_dict({})
	last_gain = {}
	save()


## « Tout débloquer » (DevMode) : pass complet en mémoire (premium, tous les paliers), jamais
## sauvegardé ; désactivé : le vrai pass est relu depuis SaveManager.
func _on_dev_unlock_changed(on: bool) -> void:
	if on == _dev_active:
		return
	if on:
		save()
		_dev_active = true
		from_dict(DevTools.build_battle_pass(self))
	else:
		_dev_active = false
		_load()
	changed.emit()


func save() -> void:
	if _dev_active:
		changed.emit()
		return
	var ml := Engine.get_main_loop() as SceneTree
	var sm: Node = ml.root.get_node_or_null(^"SaveManager") if ml != null else null
	if sm != null:
		(sm.get("data") as Dictionary)[SAVE_KEY] = to_dict()
		sm.call("save")
	changed.emit()


func _load() -> void:
	if _dev_active:
		return
	var ml := Engine.get_main_loop() as SceneTree
	var sm: Node = ml.root.get_node_or_null(^"SaveManager") if ml != null else null
	if sm == null:
		return
	if (sm.get("data") as Dictionary).is_empty() and sm.has_method("load_save"):
		sm.call("load_save")
	var d: Variant = (sm.get("data") as Dictionary).get(SAVE_KEY)
	from_dict(d if d is Dictionary else {})
