extends Node
## Profil permanent du joueur (autoload `Profile`) : arsenal (armes en réserve), objets
## extraits, arsenal de départ, monnaies et skins. Persisté dans SaveManager.data["profile"].
##
## Cycle d'un raid :
##   set_loadout(uids) → start_raid() (les armes quittent la réserve : elles sont « en jeu »)
##   → finish_extraction(armes, sac) : tout revient dans la réserve (+ gemmes gagnées)
##   → ou finish_death() : rien ne revient. Quitter le jeu pendant un raid = mort.
## Si la réserve ne contient plus aucune arme, un pistolet de départ est offert (ensure_starter).

signal changed
signal gems_changed(gems: int)

const SAVE_KEY := "profile"

## Armes en réserve : [{ "uid": int, "id": String }]
var weapons: Array[Dictionary] = []
## Arsenal de départ choisi : uids (références dans `weapons`).
var loadout: Array[int] = []
## Objets extraits (hors armes) : id → quantité.
var items: Dictionary = {}
var gems: int = 0
var dollars: int = 0
var skins_owned: Array[StringName] = []
## Skin de personnage porté (vide = apparence par défaut).
var skin_character: StringName = &""
## Skin d'arme par catégorie : String(category) → skin id ; clé "any" = toutes les armes.
var skin_weapons: Dictionary = {}
var stats: Dictionary = {"raids": 0, "extractions": 0, "deaths": 0}
var raid_in_progress: bool = false
## Armes emportées dans le raid en cours (ids), pour le résumé de mort.
var raid_weapon_ids: Array[StringName] = []
var _next_uid: int = 1


func _ready() -> void:
	_load.call_deferred()


# --- Réserve d'armes ------------------------------------------------------------

func add_weapon(id: StringName) -> int:
	if not WeaponCatalog.has_weapon(id):
		push_warning("Profile: arme inconnue %s" % id)
		return -1
	var uid := _next_uid
	_next_uid += 1
	weapons.append({"uid": uid, "id": String(id)})
	return uid


func remove_weapon(uid: int) -> bool:
	for i in weapons.size():
		if int(weapons[i]["uid"]) == uid:
			weapons.remove_at(i)
			loadout.erase(uid)
			return true
	return false


func weapon_id_of(uid: int) -> StringName:
	for e: Dictionary in weapons:
		if int(e["uid"]) == uid:
			return StringName(str(e["id"]))
	return &""


func get_weapon_data(uid: int) -> WeaponData:
	return WeaponCatalog.get_weapon(weapon_id_of(uid))


## Réserve triée (rareté décroissante, puis catégorie) : [{uid, id, data: WeaponData}].
func get_stash_weapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in weapons:
		var w := WeaponCatalog.get_weapon(StringName(str(e["id"])))
		if w != null:
			out.append({"uid": int(e["uid"]), "id": w.id, "data": w})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa: WeaponData = a["data"]
		var wb: WeaponData = b["data"]
		if wa.rarity != wb.rarity:
			return wa.rarity > wb.rarity
		var ca := WeaponData.CATEGORIES.find(wa.category)
		var cb := WeaponData.CATEGORIES.find(wb.category)
		return ca < cb if ca != cb else int(a["uid"]) < int(b["uid"]))
	return out


static func loadout_slots() -> int:
	return int(Balance.get_value("arsenal", "loadout_slots", 3))


## Fixe l'arsenal de départ (uids inconnus ignorés, tronqué au nombre d'emplacements).
func set_loadout(uids: Array[int]) -> void:
	loadout.clear()
	for u: int in uids:
		if loadout.size() >= loadout_slots():
			break
		if not weapon_id_of(u).is_empty() and not loadout.has(u):
			loadout.append(u)
	save()


func get_loadout_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for u: int in loadout:
		var w := get_weapon_data(u)
		if w != null:
			out.append(w)
	return out


func can_start_raid() -> bool:
	return not get_loadout_weapons().is_empty()


## Offre un pistolet de départ si la réserve ne contient aucune arme. Renvoie true si offert.
func ensure_starter() -> bool:
	if not weapons.is_empty() or raid_in_progress:
		return false
	var uid := add_weapon(WeaponCatalog.STARTER_ID)
	if uid > 0 and loadout.is_empty():
		loadout.append(uid)
	return uid > 0


# --- Raid -----------------------------------------------------------------------

## Lance le raid : retire l'arsenal de départ de la réserve et le renvoie (ordre des emplacements).
## Arsenal vide → l'arme la mieux classée de la réserve est prise d'office.
func start_raid() -> Array[WeaponData]:
	if loadout.is_empty():
		var stash := get_stash_weapons()
		if not stash.is_empty():
			loadout.append(int(stash[0]["uid"]))
	var out: Array[WeaponData] = []
	raid_weapon_ids.clear()
	for u: int in loadout.duplicate():
		var w := get_weapon_data(u)
		if w != null:
			out.append(w)
			raid_weapon_ids.append(w.id)
		remove_weapon(u)
	loadout.clear()
	raid_in_progress = true
	stats["raids"] = int(stats.get("raids", 0)) + 1
	save()
	return out


## Extraction réussie : armes portées + contenu du sac reviennent dans la réserve.
## Renvoie un résumé {weapons: Array[StringName], items: Dictionary, value: int, gems: int}.
func finish_extraction(carried_weapon_ids: Array[StringName], bag: Inventory) -> Dictionary:
	var got_weapons: Array[StringName] = []
	var got_items: Dictionary = {}
	var value := 0
	for id: StringName in carried_weapon_ids:
		if add_weapon(id) > 0:
			got_weapons.append(id)
	if bag != null:
		for i in bag.capacity():
			var slot: Dictionary = bag.get_slot(i)
			if slot.is_empty():
				continue
			var item: ItemData = slot.get("item")
			var count: int = int(slot.get("count", 1))
			if item == null:
				continue
			if item.is_weapon():
				for _n in count:
					if add_weapon(item.weapon_id) > 0:
						got_weapons.append(item.weapon_id)
			else:
				items[String(item.id)] = int(items.get(String(item.id), 0)) + count
				got_items[item.id] = int(got_items.get(item.id, 0)) + count
			value += item.value * count
	var earned := extraction_gems(value)
	gems += earned
	dollars += value
	raid_in_progress = false
	raid_weapon_ids.clear()
	stats["extractions"] = int(stats.get("extractions", 0)) + 1
	ensure_starter()
	save()
	gems_changed.emit(gems)
	return {"weapons": got_weapons, "items": got_items, "value": value, "gems": earned}


## Mort (ou abandon) : l'arsenal emporté et le butin sont perdus.
## Renvoie {lost_weapons: Array[StringName], starter_given: bool}.
func finish_death() -> Dictionary:
	var lost := raid_weapon_ids.duplicate()
	raid_in_progress = false
	raid_weapon_ids.clear()
	stats["deaths"] = int(stats.get("deaths", 0)) + 1
	var given := ensure_starter()
	save()
	return {"lost_weapons": lost, "starter_given": given}


## Gemmes gagnées à l'extraction (balance.cfg [shop]).
static func extraction_gems(loot_value: int) -> int:
	var base := int(Balance.get_value("shop", "gems_per_extraction", 3))
	var per := float(Balance.get_value("shop", "gems_per_loot_value", 0.004))
	var cap := int(Balance.get_value("shop", "gems_per_extraction_max", 15))
	return mini(base + int(floor(loot_value * per)), cap)


# --- Monnaie et skins -----------------------------------------------------------

func add_gems(n: int) -> void:
	gems = maxi(gems + n, 0)
	save()
	gems_changed.emit(gems)


func owns_skin(id: StringName) -> bool:
	var s := SkinData.get_skin(id)
	return skins_owned.has(id) or (s != null and s.price_gems <= 0)


## Achat d'un skin en gemmes. Renvoie false si inconnu, déjà possédé ou pas assez de gemmes.
func buy_skin(id: StringName) -> bool:
	var s := SkinData.get_skin(id)
	if s == null or owns_skin(id) or gems < s.price_gems:
		return false
	gems -= s.price_gems
	skins_owned.append(id)
	save()
	gems_changed.emit(gems)
	return true


func equip_character_skin(id: StringName) -> bool:
	if not String(id).is_empty() and not owns_skin(id):
		return false
	skin_character = id
	save()
	return true


func get_character_skin() -> SkinData:
	return SkinData.get_skin(skin_character) if not String(skin_character).is_empty() else null


## Équipe un skin d'arme pour sa catégorie (id vide + catégorie = retirer).
func equip_weapon_skin(id: StringName, category: StringName = &"") -> bool:
	if String(id).is_empty():
		skin_weapons.erase(String(category))
		save()
		return true
	var s := SkinData.get_skin(id)
	if s == null or s.kind != SkinData.KIND_WEAPON or not owns_skin(id):
		return false
	skin_weapons[String(s.weapon_category)] = String(id)
	save()
	return true


## Skin à appliquer à une arme de cette catégorie (catégorie précise prioritaire sur « any »).
func get_weapon_skin(category: StringName) -> SkinData:
	var id := str(skin_weapons.get(String(category), skin_weapons.get("any", "")))
	return SkinData.get_skin(StringName(id)) if not id.is_empty() else null


# --- Sauvegarde -----------------------------------------------------------------

func to_dict() -> Dictionary:
	var sk: Array = []
	for s: StringName in skins_owned:
		sk.append(String(s))
	var rw: Array = []
	for s: StringName in raid_weapon_ids:
		rw.append(String(s))
	return {
		"weapons": weapons.duplicate(true), "loadout": loadout.duplicate(), "items": items.duplicate(),
		"gems": gems, "dollars": dollars, "skins_owned": sk, "skin_character": String(skin_character),
		"skin_weapons": skin_weapons.duplicate(), "stats": stats.duplicate(),
		"raid_in_progress": raid_in_progress, "raid_weapon_ids": rw, "next_uid": _next_uid,
	}


func from_dict(d: Dictionary) -> void:
	weapons.clear()
	for e: Variant in d.get("weapons", []):
		if e is Dictionary and WeaponCatalog.has_weapon(StringName(str(e.get("id", "")))):
			weapons.append({"uid": int(e.get("uid", 0)), "id": str(e.get("id"))})
	loadout.clear()
	for u: Variant in d.get("loadout", []):
		if not weapon_id_of(int(u)).is_empty():
			loadout.append(int(u))
	var it: Variant = d.get("items", {})
	items = (it as Dictionary).duplicate() if it is Dictionary else {}
	gems = int(d.get("gems", int(Balance.get_value("shop", "starting_gems", 0))))
	dollars = int(d.get("dollars", 0))
	skins_owned.clear()
	for s: Variant in d.get("skins_owned", []):
		skins_owned.append(StringName(str(s)))
	skin_character = StringName(str(d.get("skin_character", "")))
	var sw: Variant = d.get("skin_weapons", {})
	skin_weapons = (sw as Dictionary).duplicate() if sw is Dictionary else {}
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		stats.merge(st, true)
	raid_in_progress = bool(d.get("raid_in_progress", false))
	raid_weapon_ids.clear()
	for s: Variant in d.get("raid_weapon_ids", []):
		raid_weapon_ids.append(StringName(str(s)))
	_next_uid = int(d.get("next_uid", 1))
	for e: Dictionary in weapons:
		_next_uid = maxi(_next_uid, int(e["uid"]) + 1)


## Profil neuf : arsenal de départ (balance.cfg [arsenal] starting_weapons).
func reset_new() -> void:
	from_dict({})
	for id: Variant in Balance.get_value("arsenal", "starting_weapons", [String(WeaponCatalog.STARTER_ID)]):
		var uid := add_weapon(StringName(str(id)))
		if uid > 0 and loadout.size() < loadout_slots():
			loadout.append(uid)
	ensure_starter()


func save() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	(sm.get("data") as Dictionary)[SAVE_KEY] = to_dict()
	sm.call("save")
	changed.emit()


func _load() -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		reset_new()
		return
	if (sm.get("data") as Dictionary).is_empty() and sm.has_method("load_save"):
		sm.call("load_save")
	var d: Variant = (sm.get("data") as Dictionary).get(SAVE_KEY)
	if d is Dictionary:
		from_dict(d)
		# Jeu quitté en plein raid : compte comme une mort (pas de duplication d'armes).
		if raid_in_progress:
			finish_death()
		ensure_starter()
	else:
		reset_new()
	save()
