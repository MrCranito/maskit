extends Node
## Profil permanent du joueur (autoload `Profile`) : arsenal (armes en réserve), objets
## extraits, arsenal de départ, monnaies et skins. Persisté dans SaveManager.data["profile"].
##
## Cycle d'un raid :
##   set_loadout(uids) → start_raid() (les armes quittent la réserve : elles sont « en jeu »)
##   → finish_extraction(armes, sac) : tout revient dans la réserve (+ gemmes gagnées)
##   → ou finish_death() : rien ne revient. Quitter le jeu pendant un raid = mort.
## Si la réserve ne contient plus aucune arme, un pistolet de départ est offert (ensure_starter).
##
## Économie (refonte n°3, scripts/economy/*) : l'OR (pièces, `gold` ; ancien `dollars`) se gagne
## en vendant au marchand (sell_item / sell_weapon) et sert à acheter des armes (buy_weapon) selon
## leurs règles (WeaponData.unlock_mode : shop / kill / drop). Les victimes sont comptées par kind
## (`kills_by_kind`, écoute d'EventBus.enemy_died), qu'on meure ou non ; sauvegardées en fin de raid.
## Artisanat : craft(recipe_id) consomme des objets de la réserve (RecipeBook) ; les soins de la
## réserve partent dans le sac de raid au lancement (pack_consumables, [crafting]).

signal changed
signal gems_changed(gems: int)
signal gold_changed(gold: int)
## Seuil de victimes atteint : l'arme devient achetable à l'armurerie (message en raid).
signal weapon_unlocked(weapon_id: StringName)
signal crafted(recipe_id: StringName)
## Niveau de raider gagné (progression permanente, RaiderProgress) : nouveaux déblocages du niveau.
signal raider_level_up(level: int, unlocks: Array)

const SAVE_KEY := "profile"

## Armes en réserve : [{ "uid": int, "id": String }]
var weapons: Array[Dictionary] = []
## Arsenal de départ choisi : uids (références dans `weapons`) : jusqu'à `loadout_slots()`
## armes (slot weapon) + 1 équipement (slot gadget : grenade, mine, C4, drone).
var loadout: Array[int] = []
## Équipement emporté dans le raid en cours (null = aucun), fixé par start_raid().
var raid_gadget: WeaponData = null
## Objets extraits (hors armes) : id → quantité.
var items: Dictionary = {}
var gems: int = 0
## Pièces d'or (marchand → armurerie, artisanat).
var gold: int = 0
## Compatibilité : ancien compteur « dollars » = l'or.
var dollars: int:
	get:
		return gold
	set(v):
		gold = v
## Victimes par kind d'ennemi (String(kind) → n), tous raids confondus.
var kills_by_kind: Dictionary = {}
## Victimes du raid en cours (String(kind) → n) : encart de fin de raid.
var raid_kills: Dictionary = {}
## Armes « kill » dont le seuil est atteint (achetables), dans l'ordre de déblocage.
var unlocked_weapons: Array[StringName] = []
## Armes achetées au moins une fois à l'armurerie (statistiques).
var bought_weapons: Array[StringName] = []
## Emporter les soins de la réserve dans le sac de raid au lancement.
var pack_consumables: bool = true
## Emporter les clefs de la réserve au prochain raid (choix de l'arsenal de départ). Elles
## suivent la règle du sac : perdues à la mort, rendues à l'extraction si elles n'ont pas servi.
var pack_keys: bool = false
## Consommables mis dans le sac au lancement du raid en cours (id → n).
var raid_packed: Dictionary = {}
var skins_owned: Array[StringName] = []
## Boutique : bonus de premier achat consommé, packs à contenu achetés (Store).
var shop_first_bonus_used: bool = false
var bundles_bought: Array[StringName] = []
## Coffres de skins gratuits : en stock, extractions vers le prochain, coffres sans Épique.
var free_chests: int = 0
var chest_progress: int = 0
var chest_pity_count: int = 0
## Skin de personnage porté (vide = apparence par défaut).
var skin_character: StringName = &""
## Skin d'arme par catégorie : String(category) → skin id ; clé "any" = toutes les armes.
var skin_weapons: Dictionary = {}
var stats: Dictionary = {"raids": 0, "extractions": 0, "deaths": 0}
## XP de raider cumulée (progression permanente, voir RaiderProgress).
var raider_xp: int = 0
var raid_in_progress: bool = false
## Armes emportées dans le raid en cours (ids), pour le résumé de mort.
var raid_weapon_ids: Array[StringName] = []
var _next_uid: int = 1


func _ready() -> void:
	_load.call_deferred()
	var eb: Node = get_node_or_null(^"/root/EventBus")
	if eb != null and eb.has_signal(&"enemy_died"):
		eb.connect(&"enemy_died", _on_enemy_died)
	DevMode.notifier.changed.connect(_on_dev_mode_changed)


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


## Emplacements d'armes de l'arsenal de départ : dépendent du niveau de raider
## (RaiderProgress, [raider] start_loadout_slots + déblocages), plafonnés par [arsenal] loadout_slots.
static func loadout_slots() -> int:
	return RaiderProgress.loadout_slots_at(RaiderProgress.current_level())


## Niveau de raider actuel.
func raider_level() -> int:
	return RaiderProgress.level_for_xp(raider_xp)


## Ajoute de l'XP de raider. Donne les récompenses uniques (gemmes, or) des niveaux franchis et
## émet raider_level_up pour chacun. Renvoie {xp, level_before, level_after, unlocks: Array}.
func add_raider_xp(amount: int) -> Dictionary:
	var before := raider_level()
	raider_xp += maxi(amount, 0)
	var after := raider_level()
	var gained: Array = []
	for lv in range(before + 1, after + 1):
		var ul: Array[Dictionary] = RaiderProgress.unlocks_at(lv)
		for d: Dictionary in ul:
			match d["kind"]:
				RaiderProgress.KIND_GEMS:
					add_gems(int(d.get("value", 0)))
				RaiderProgress.KIND_GOLD:
					add_gold(int(d.get("value", 0)))
			gained.append(d)
		raider_level_up.emit(lv, ul)
	save()
	changed.emit()
	return {"xp": maxi(amount, 0), "level_before": before, "level_after": after, "unlocks": gained}


## Fixe l'arsenal de départ : uids inconnus ignorés, au plus loadout_slots() armes et
## gadget_slots() équipement (les suivants sont ignorés).
func set_loadout(uids: Array[int]) -> void:
	loadout.clear()
	var nw := 0
	var ng := 0
	for u: int in uids:
		var w := get_weapon_data(u)
		if w == null or loadout.has(u):
			continue
		if w.is_gadget():
			if ng >= gadget_slots():
				continue
			ng += 1
		else:
			if nw >= loadout_slots():
				continue
			nw += 1
		loadout.append(u)
	save()


static func gadget_slots() -> int:
	return int(Balance.get_value("arsenal", "gadget_slots", 1))


## Armes (hors équipement) de l'arsenal de départ, dans l'ordre.
func get_loadout_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for u: int in loadout:
		var w := get_weapon_data(u)
		if w != null and not w.is_gadget():
			out.append(w)
	return out


## Équipement de l'arsenal de départ (null si aucun).
func get_loadout_gadget() -> WeaponData:
	for u: int in loadout:
		var w := get_weapon_data(u)
		if w != null and w.is_gadget():
			return w
	return null


func can_start_raid() -> bool:
	return not get_loadout_weapons().is_empty()


## Offre un pistolet de départ si la réserve ne contient aucune arme. Renvoie true si offert.
func ensure_starter() -> bool:
	if raid_in_progress:
		return false
	for e: Dictionary in get_stash_weapons():
		if not (e["data"] as WeaponData).is_gadget():
			return false
	var uid := add_weapon(WeaponCatalog.STARTER_ID)
	if uid > 0 and loadout.is_empty():
		loadout.append(uid)
	return uid > 0


# --- Raid -----------------------------------------------------------------------

## Lance le raid : retire l'arsenal de départ de la réserve et le renvoie (ordre des emplacements).
## Arsenal vide → l'arme la mieux classée de la réserve est prise d'office.
func start_raid() -> Array[WeaponData]:
	if get_loadout_weapons().is_empty():
		for e: Dictionary in get_stash_weapons():
			if not (e["data"] as WeaponData).is_gadget():
				loadout.append(int(e["uid"]))
				break
	var out: Array[WeaponData] = []
	raid_gadget = null
	raid_weapon_ids.clear()
	for u: int in loadout.duplicate():
		var w := get_weapon_data(u)
		if w != null:
			if w.is_gadget():
				raid_gadget = w
			else:
				out.append(w)
			raid_weapon_ids.append(w.id)
		remove_weapon(u)
	loadout.clear()
	raid_in_progress = true
	raid_kills.clear()
	stats["raids"] = int(stats.get("raids", 0)) + 1
	var gs: Node = get_node_or_null(^"/root/GameState")
	pack_consumables_into(gs.get("raid_inventory") as Inventory if gs != null else null)
	pack_keys_into(gs.get("raid_inventory") as Inventory if gs != null else null)
	save()
	return out


## Extraction réussie : armes portées + contenu du sac reviennent dans la réserve.
## Renvoie un résumé {weapons: Array[StringName], items: Dictionary, value: int (or estimé au
## marchand), loot_value: int (valeur brute), gems: int, unlock_kills: Array (Economy.kill_report)}.
## Aucune pièce d'or n'est donnée : le butin se vend au marchand.
func finish_extraction(carried_weapon_ids: Array[StringName], bag: Inventory) -> Dictionary:
	var got_weapons: Array[StringName] = []
	var got_items: Dictionary = {}
	var value := 0
	var estimate := 0
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
			estimate += Economy.item_sell_price(item) * count
	# Plus d'or automatique : le butin se vend au marchand. Gemmes selon la valeur du butin.
	var earned := extraction_gems(value)
	gems += earned
	var report := Economy.kill_report(raid_kills, kills_by_kind)
	raid_in_progress = false
	raid_weapon_ids.clear()
	raid_packed.clear()
	stats["extractions"] = int(stats.get("extractions", 0)) + 1
	var chest := add_chest_progress()
	ensure_starter()
	save()
	gems_changed.emit(gems)
	return {"weapons": got_weapons, "items": got_items, "value": estimate, "loot_value": value,
		"gems": earned, "unlock_kills": report, "chest": chest}


## Une extraction réussie de plus vers le prochain coffre gratuit ([chests] every_extractions).
## Renvoie true si un coffre vient d'être gagné.
func add_chest_progress() -> bool:
	chest_progress += 1
	if chest_progress < Store.chest_every():
		return false
	chest_progress = 0
	free_chests += 1
	return true


## Mort (ou abandon) : l'arsenal emporté et le butin sont perdus.
## Renvoie {lost_weapons: Array[StringName], starter_given: bool, unlock_kills: Array (Economy.kill_report),
## lost_estimate: int (or estimé du sac perdu)}. (« unlock_kills » : « kills » est l'entier du pass de combat.)
func finish_death() -> Dictionary:
	var lost := raid_weapon_ids.duplicate()
	var report := Economy.kill_report(raid_kills, kills_by_kind)
	var gs: Node = get_node_or_null(^"/root/GameState")
	var lost_estimate := Economy.estimate_inventory(gs.get("raid_inventory") as Inventory if gs != null else null)
	raid_in_progress = false
	raid_weapon_ids.clear()
	raid_packed.clear()
	stats["deaths"] = int(stats.get("deaths", 0)) + 1
	var given := ensure_starter()
	save()
	return {"lost_weapons": lost, "starter_given": given, "unlock_kills": report, "lost_estimate": lost_estimate}


## Gemmes gagnées à l'extraction (balance.cfg [shop]).
static func extraction_gems(loot_value: int) -> int:
	var base := int(Balance.get_value("shop", "gems_per_extraction", 3))
	var per := float(Balance.get_value("shop", "gems_per_loot_value", 0.004))
	var cap := int(Balance.get_value("shop", "gems_per_extraction_max", 15))
	return mini(base + int(floor(loot_value * per)), cap)


# --- Or, marchand, armurerie ----------------------------------------------------

func add_gold(n: int) -> void:
	gold = maxi(gold + n, 0)
	save()
	gold_changed.emit(gold)


func item_count(id: StringName) -> int:
	return int(items.get(String(id), 0))


## Ajoute des objets à la réserve (récompenses, artisanat). Armes (wpn_*) → réserve d'armes.
func add_item(id: StringName, n: int = 1) -> void:
	if n <= 0:
		return
	var it := LootDB.get_item(id)
	if it != null and it.is_weapon():
		for _k in n:
			add_weapon(it.weapon_id)
	else:
		items[String(id)] = item_count(id) + n
	save()


## Retire jusqu'à n objets ; renvoie le nombre retiré.
func remove_item(id: StringName, n: int = 1) -> int:
	var have := item_count(id)
	var k := mini(have, maxi(n, 0))
	if k <= 0:
		return 0
	if have - k <= 0:
		items.erase(String(id))
	else:
		items[String(id)] = have - k
	return k


## Réserve d'objets triée (rareté décroissante, puis nom) : [{id, item: ItemData, count}].
func get_stash_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in items:
		var it := LootDB.get_item(StringName(str(k)))
		var n := int(items[k])
		if it != null and n > 0:
			out.append({"id": it.id, "item": it, "count": n})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia: ItemData = a["item"]
		var ib: ItemData = b["item"]
		if ia.rarity != ib.rarity:
			return ia.rarity > ib.rarity
		return ia.display_name < ib.display_name)
	return out


## Vend n unités d'un objet de la réserve au marchand. Renvoie l'or gagné (0 = rien vendu).
func sell_item(id: StringName, n: int = 1) -> int:
	var it := LootDB.get_item(id)
	if it == null or it.is_weapon():
		return 0
	var k := remove_item(id, n)
	if k <= 0:
		return 0
	var g := Economy.item_sell_price(it) * k
	gold += g
	stats["items_sold"] = int(stats.get("items_sold", 0)) + k
	save()
	gold_changed.emit(gold)
	return g


## Exemplaires possédés d'un modèle d'arme.
func weapon_count(id: StringName) -> int:
	var n := 0
	for e: Dictionary in weapons:
		if StringName(str(e["id"])) == id:
			n += 1
	return n


## Une arme ne se vend qu'en double (on garde toujours un exemplaire), jamais une arme permanente.
func can_sell_weapon(uid: int) -> bool:
	var w := get_weapon_data(uid)
	return w != null and not w.permanent and weapon_count(w.id) > 1 and Economy.weapon_sell_price(w) > 0


## Vend un exemplaire en double (uid). Renvoie l'or gagné (0 = refus).
func sell_weapon(uid: int) -> int:
	if not can_sell_weapon(uid):
		return 0
	var w := get_weapon_data(uid)
	var g := Economy.weapon_sell_price(w)
	remove_weapon(uid)
	gold += g
	save()
	gold_changed.emit(gold)
	return g


## Uid d'un exemplaire vendable de ce modèle (hors arsenal de départ si possible), -1 sinon.
func spare_weapon_uid(id: StringName) -> int:
	var cands: Array[int] = []
	for e: Dictionary in weapons:
		if StringName(str(e["id"])) == id:
			cands.append(int(e["uid"]))
	if cands.size() <= 1:
		return -1
	for u: int in cands:
		if not loadout.has(u):
			return u
	return cands[cands.size() - 1]


## État d'une arme à l'armurerie (Economy.weapon_status avec les kills du profil).
func weapon_shop_status(id: StringName) -> Dictionary:
	return Economy.weapon_status(WeaponCatalog.get_weapon(id), kills_by_kind)


func is_weapon_buyable(id: StringName) -> bool:
	return weapon_shop_status(id).get("state") == Economy.STATE_BUYABLE


## Achat à l'armurerie : refusé si inconnue, Légendaire / « drop », pas encore débloquée ou or
## insuffisant. L'arme rejoint la réserve.
func buy_weapon(id: StringName) -> bool:
	var w := WeaponCatalog.get_weapon(id)
	if w == null or not is_weapon_buyable(id) or not can_afford(&"gold", w.price_gold):
		return false
	if add_weapon(id) <= 0:
		return false
	debit(&"gold", w.price_gold)
	if not bought_weapons.has(id):
		bought_weapons.append(id)
	save()
	return true


## Victime d'un ennemi de ce kind (comptée même si le raid se termine par une mort).
## Renvoie les armes qui deviennent achetables (signal weapon_unlocked pour chacune).
## Pas de sauvegarde ici : le compteur est écrit en fin de raid (finish_*).
func record_kill(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if String(kind).is_empty():
		return out
	var k := String(kind)
	kills_by_kind[k] = int(kills_by_kind.get(k, 0)) + 1
	raid_kills[k] = int(raid_kills.get(k, 0)) + 1
	for w: WeaponData in Economy.weapons_unlocked_by(kind):
		if not unlocked_weapons.has(w.id) and int(kills_by_kind[k]) >= maxi(w.unlock_kills, 1):
			unlocked_weapons.append(w.id)
			out.append(w.id)
			weapon_unlocked.emit(w.id)
	return out


func _on_enemy_died(enemy: Node, _pos: Vector2 = Vector2.ZERO) -> void:
	if enemy == null or not enemy.is_in_group(&"enemy_units"):
		return
	var d: Variant = enemy.get(&"data")
	if d is Resource and (d as Resource).get(&"kind") != null:
		record_kill(StringName(str((d as Resource).get(&"kind"))))


# --- Artisanat ------------------------------------------------------------------

func can_craft(recipe_id: StringName) -> bool:
	return RecipeBook.can_craft(RecipeBook.get_recipe(recipe_id), items, balance_of(&"gold"))


## Fabrique une recette : consomme ingrédients + or ; le résultat va dans la réserve
## (objet → items, équipement → réserve d'armes). Renvoie false si impossible.
func craft(recipe_id: StringName) -> bool:
	var r := RecipeBook.get_recipe(recipe_id)
	if not RecipeBook.can_craft(r, items, balance_of(&"gold")):
		return false
	var use := RecipeBook.plan(r, items)
	if use.is_empty() and not r.ingredients.is_empty():
		return false
	for id: Variant in use:
		remove_item(StringName(str(id)), int(use[id]))
	debit(&"gold", r.gold_cost)
	for _k in maxi(r.result_count, 1):
		if r.is_weapon_result():
			add_weapon(r.result_weapon_id)
	if not r.is_weapon_result():
		items[String(r.result_item_id)] = item_count(r.result_item_id) + maxi(r.result_count, 1)
	stats["crafted"] = int(stats.get("crafted", 0)) + 1
	save()
	crafted.emit(recipe_id)
	return true


# --- Consommables emportés ------------------------------------------------------

static func raid_consumables_max() -> int:
	return int(Balance.get_value("crafting", "raid_consumables_max", 4))


## Soins de la réserve qui partiront dans le sac au prochain lancement (meilleurs soins d'abord) :
## [{item: ItemData, count}] — vide si pack_consumables est désactivé.
func consumables_preview() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not pack_consumables:
		return out
	var list: Array[ItemData] = []
	for k: Variant in items:
		var it := LootDB.get_item(StringName(str(k)))
		if it != null and it.is_usable() and int(items[k]) > 0:
			list.append(it)
	list.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		return a.heal_amount > b.heal_amount if a.heal_amount != b.heal_amount else String(a.id) < String(b.id))
	var left := raid_consumables_max()
	for it: ItemData in list:
		if left <= 0:
			break
		var n := mini(item_count(it.id), left)
		out.append({"item": it, "count": n})
		left -= n
	return out


## Met les soins prévus dans le sac de raid (ils quittent la réserve : perdus à la mort,
## rendus à l'extraction s'ils n'ont pas servi). Renvoie {id: n} réellement emportés.
func pack_consumables_into(bag: Inventory) -> Dictionary:
	raid_packed.clear()
	if bag == null:
		return raid_packed
	for e: Dictionary in consumables_preview():
		var it: ItemData = e["item"]
		var added := bag.add_item(it, int(e["count"]))
		if added > 0:
			remove_item(it.id, added)
			raid_packed[String(it.id)] = added
	return raid_packed


func set_pack_consumables(on: bool) -> void:
	pack_consumables = on
	save()


# --- Clefs emportées ------------------------------------------------------------

## Clefs de la réserve (toutes, triées par nom) : [{item: ItemData, count}].
func keys_in_reserve() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in items:
		var it := LootDB.get_item(StringName(str(k)))
		if it != null and it.is_key() and int(items[k]) > 0:
			out.append({"item": it, "count": int(items[k])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemData).display_name < (b["item"] as ItemData).display_name)
	return out


## Clefs qui partiront dans le sac au prochain lancement (vide si pack_keys est désactivé).
func keys_preview() -> Array[Dictionary]:
	return keys_in_reserve() if pack_keys else ([] as Array[Dictionary])


## Met les clefs prévues dans le sac de raid (elles quittent la réserve). Ajoute à raid_packed.
func pack_keys_into(bag: Inventory) -> Dictionary:
	var packed := {}
	if bag == null:
		return packed
	for e: Dictionary in keys_preview():
		var it: ItemData = e["item"]
		var added := bag.add_item(it, int(e["count"]))
		if added > 0:
			remove_item(it.id, added)
			packed[String(it.id)] = added
			raid_packed[String(it.id)] = int(raid_packed.get(String(it.id), 0)) + added
	return packed


func set_pack_keys(on: bool) -> void:
	pack_keys = on
	save()


# --- Monnaie et skins -----------------------------------------------------------

## Solde dépensable (&"gems" ou &"gold") : le vrai solde, ou DevMode.UNLIMITED en mode développeur.
## Les écrans testent « assez de … ? » avec can_afford() / balance_of(), jamais gems / gold.
func balance_of(currency: StringName) -> int:
	if DevMode.is_unlimited():
		return DevMode.UNLIMITED
	match currency:
		&"gems":
			return gems
		&"gold":
			return gold
	return 0


func can_afford(currency: StringName, amount: int) -> bool:
	return amount <= 0 or balance_of(currency) >= amount


## SEUL point de débit des monnaies (gemmes, or). Mode développeur actif : rien n'est débité
## (le solde réel, seul sauvegardé, reste intact). false si solde insuffisant ou monnaie inconnue.
## Pas de sauvegarde ici : l'appelant sauvegarde l'achat complet.
func debit(currency: StringName, amount: int) -> bool:
	if amount <= 0:
		return true
	if DevMode.is_unlimited():
		return true
	match currency:
		&"gems":
			if gems < amount:
				return false
			gems -= amount
			gems_changed.emit(gems)
		&"gold":
			if gold < amount:
				return false
			gold -= amount
			gold_changed.emit(gold)
		_:
			return false
	return true


## Bascule du mode développeur : les compteurs se redessinent (∞ ou vrai solde).
func _on_dev_mode_changed(_on: bool) -> void:
	gems_changed.emit(gems)
	gold_changed.emit(gold)
	changed.emit()


func add_gems(n: int) -> void:
	gems = maxi(gems + n, 0)
	save()
	gems_changed.emit(gems)


func owns_skin(id: StringName) -> bool:
	var s := SkinData.get_skin(id)
	return skins_owned.has(id) or (s != null and s.price_gems <= 0)


## Achat d'un skin en gemmes. Renvoie false si inconnu, déjà possédé ou pas assez de gemmes.
## Ajoute un skin possédé (pack, coffre, pass) sans débiter de gemmes.
func grant_skin(id: StringName) -> void:
	if not skins_owned.has(id):
		skins_owned.append(id)
	save()


func buy_skin(id: StringName) -> bool:
	var s := SkinData.get_skin(id)
	# Skins du pass de combat : jamais achetables en gemmes (récompenses de palier).
	if s == null or s.is_pass() or owns_skin(id) or not can_afford(&"gems", s.price_gems):
		return false
	debit(&"gems", s.price_gems)
	skins_owned.append(id)
	save()
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
		"gems": gems, "gold": gold, "kills_by_kind": kills_by_kind.duplicate(),
		"unlocked_weapons": _names_to_array(unlocked_weapons), "bought_weapons": _names_to_array(bought_weapons),
		"pack_consumables": pack_consumables, "pack_keys": pack_keys,
		"skins_owned": sk, "skin_character": String(skin_character),
		"skin_weapons": skin_weapons.duplicate(), "stats": stats.duplicate(),
		"raid_in_progress": raid_in_progress, "raid_weapon_ids": rw, "next_uid": _next_uid,
		"raider_xp": raider_xp,
		"shop_first_bonus_used": shop_first_bonus_used, "bundles_bought": _names_to_array(bundles_bought),
		"free_chests": free_chests, "chest_progress": chest_progress, "chest_pity": chest_pity_count,
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
	# Ancien compteur « dollars » (extraction automatique) : devient l'or.
	gold = int(d.get("gold", d.get("dollars", int(Balance.get_value("economy", "starting_gold", 0)))))
	kills_by_kind.clear()
	var kv: Variant = d.get("kills_by_kind", {})
	if kv is Dictionary:
		for k: Variant in kv:
			kills_by_kind[str(k)] = int(kv[k])
	unlocked_weapons.clear()
	for s2: Variant in d.get("unlocked_weapons", []):
		unlocked_weapons.append(StringName(str(s2)))
	bought_weapons.clear()
	for s3: Variant in d.get("bought_weapons", []):
		bought_weapons.append(StringName(str(s3)))
	pack_consumables = bool(d.get("pack_consumables", Balance.get_value("crafting", "pack_consumables_default", true)))
	pack_keys = bool(d.get("pack_keys", LootDB.cfg().get_value(LootDB.SECTION, "pack_keys_default", false)))
	raid_kills.clear()
	raid_packed.clear()
	skins_owned.clear()
	for s: Variant in d.get("skins_owned", []):
		skins_owned.append(StringName(str(s)))
	skin_character = StringName(str(d.get("skin_character", "")))
	shop_first_bonus_used = bool(d.get("shop_first_bonus_used", false))
	bundles_bought.clear()
	for b: Variant in d.get("bundles_bought", []):
		bundles_bought.append(StringName(str(b)))
	free_chests = maxi(int(d.get("free_chests", 0)), 0)
	chest_progress = maxi(int(d.get("chest_progress", 0)), 0)
	chest_pity_count = maxi(int(d.get("chest_pity", 0)), 0)
	var sw: Variant = d.get("skin_weapons", {})
	skin_weapons = (sw as Dictionary).duplicate() if sw is Dictionary else {}
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		stats.merge(st, true)
	# Sauvegarde d'avant le niveau de raider : XP estimée à partir des statistiques.
	raider_xp = int(d.get("raider_xp", RaiderProgress.xp_from_stats(stats)))
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


static func _names_to_array(list: Array[StringName]) -> Array:
	var out: Array = []
	for s: StringName in list:
		out.append(String(s))
	return out


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
