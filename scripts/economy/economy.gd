class_name Economy
extends RefCounted
## Règles de l'économie (logique pure, sans état) : prix de vente au marchand, prix et état
## de déblocage des armes à l'armurerie, valeur estimée d'un butin.
## L'état (or, kills, déblocages) vit dans l'autoload Profile ; l'équilibrage dans
## balance.cfg [economy]. Voir docs/CONVENTIONS.md « Refonte n°3 ».

const SECTION := "economy"
const ENEMY_DIR := "res://data/enemies/"

## États d'une arme à l'armurerie.
const STATE_BUYABLE := &"buyable"     # achetable maintenant
const STATE_LOCKED := &"locked"       # mode kill, seuil pas encore atteint
const STATE_DROP_ONLY := &"drop_only" # jamais achetable (Légendaires)

static var _enemy_names: Dictionary = {}


static func cfg(key: String, def: Variant) -> Variant:
	return RecipeBook._balance(SECTION, key, def)


static func cfg_f(key: String, def: float) -> float:
	return float(cfg(key, def))


# --- Vente (marchand) -------------------------------------------------------------------

## Pièces d'or reçues pour UNE unité d'un objet (armes : prix selon la rareté).
static func item_sell_price(item: ItemData) -> int:
	if item == null:
		return 0
	if item.is_weapon():
		return weapon_sell_price(item.get_weapon())
	var ratio := cfg_f("sell_ratio", 0.5)
	return maxi(int(round(float(item.value) * ratio)), int(cfg("sell_min", 1)))


## Pièces d'or reçues pour une arme (exemplaire en double) : selon sa rareté, × le bonus des
## affixes tirés au drop ([affixes] value_bonus_per_affix).
static func weapon_sell_price(w: WeaponData) -> int:
	if w == null or w.permanent:
		return 0
	var arr: Variant = cfg("weapon_sell_by_rarity", [40, 90, 150, 350, 800])
	var a: Array = arr if arr is Array else [40, 90, 150, 350, 800]
	var base := int(a[clampi(w.rarity, 0, a.size() - 1)])
	if not w.has_rolled_affixes():
		return base
	return roundi(float(base) * Affixes.value_mult(w.rolled_affixes.size()))


## Faut-il confirmer la vente de cet objet (rareté ≥ confirm_min_rarity) ?
static func needs_confirmation(rarity: int) -> bool:
	return rarity >= int(cfg("confirm_min_rarity", 2))


## Valeur estimée au marchand d'un ensemble {id d'objet: quantité}.
static func estimate_items(items: Dictionary) -> int:
	var total := 0
	for k: Variant in items:
		total += item_sell_price(LootDB.get_item(StringName(str(k)))) * int(items[k])
	return total


## Valeur estimée au marchand d'un sac de raid (armes comprises).
static func estimate_inventory(bag: Inventory) -> int:
	var total := 0
	if bag == null:
		return 0
	for i in bag.capacity():
		var s: Dictionary = bag.get_slot(i)
		if not s.is_empty() and s.get("item") != null:
			total += item_sell_price(s["item"] as ItemData) * int(s.get("count", 1))
	return total


# --- Armurerie ----------------------------------------------------------------------------

## Nom affiché d'un kind d'ennemi (data/enemies/<kind>.tres), mis en cache.
static func enemy_name(kind: StringName) -> String:
	if _enemy_names.has(kind):
		return String(_enemy_names[kind])
	var n := String(kind).capitalize()
	var p := ENEMY_DIR + String(kind) + ".tres"
	if ResourceLoader.exists(p):
		var d := load(p) as Resource
		if d != null and str(d.get("display_name")) != "":
			n = str(d.get("display_name"))
	_enemy_names[kind] = n
	return n


## Pluriel simple d'un nom d'ennemi (« Tireur embusqué » → « Tireurs embusqués »,
## « Chef de bande » → « Chefs de bande ») quand n > 1.
static func plural(name: String, n: int) -> String:
	if n <= 1 or name.is_empty():
		return name
	var words := name.split(" ")
	var stop := ["au", "aux", "de", "du", "des", "à", "en", "la", "le"]
	for i in words.size():
		if i > 0 and stop.has(words[i].to_lower()):
			break
		var wd: String = words[i]
		if not (wd.ends_with("s") or wd.ends_with("x") or wd.ends_with("z")):
			words[i] = wd + "s"
		if i >= 1:
			break
	return " ".join(words)


## État d'une arme à l'armurerie selon les kills {kind: n} :
## {state, mode, price, kills, needed, enemy, enemy_name, text}.
static func weapon_status(w: WeaponData, kills: Dictionary) -> Dictionary:
	var st := {"state": STATE_DROP_ONLY, "mode": WeaponData.UNLOCK_DROP, "price": 0, "kills": 0, "needed": 0,
		"enemy": &"", "enemy_name": "", "text": ""}
	if w == null:
		return st
	st["mode"] = w.unlock_mode
	st["price"] = w.price_gold
	if w.unlock_mode == WeaponData.UNLOCK_DROP or w.rarity >= WeaponData.Rarity.LEGENDAIRE or w.price_gold <= 0:
		st["state"] = STATE_DROP_ONLY
		st["mode"] = WeaponData.UNLOCK_DROP
		st["text"] = ("%s : uniquement en butin" % WeaponData.RARITY_NAMES[clampi(w.rarity, 0, 4)]) \
			if w.rarity >= WeaponData.Rarity.LEGENDAIRE else "Uniquement en butin"
		return st
	if w.unlock_mode == WeaponData.UNLOCK_KILL:
		var need := maxi(w.unlock_kills, 1)
		var have := int(kills.get(String(w.unlock_enemy_kind), kills.get(w.unlock_enemy_kind, 0)))
		st["kills"] = mini(have, need)
		st["needed"] = need
		st["enemy"] = w.unlock_enemy_kind
		st["enemy_name"] = enemy_name(w.unlock_enemy_kind)
		if have < need:
			st["state"] = STATE_LOCKED
			st["text"] = "Tue %d %s pour débloquer (%d/%d)" % [need, plural(st["enemy_name"], need), mini(have, need), need]
			return st
		st["state"] = STATE_BUYABLE
		st["text"] = "Débloquée : %d %s abattu%s" % [need, plural(st["enemy_name"], need), "s" if need > 1 else ""]
		return st
	st["state"] = STATE_BUYABLE
	st["text"] = "En vente"
	return st


## Armes à débloquer par kill de ce kind : [WeaponData].
static func weapons_unlocked_by(kind: StringName) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w: WeaponData in WeaponCatalog.all():
		if w.unlock_mode == WeaponData.UNLOCK_KILL and w.unlock_enemy_kind == kind and w.rarity < WeaponData.Rarity.LEGENDAIRE:
			out.append(w)
	return out


## Kinds d'ennemis qui comptent pour un déblocage.
static func unlock_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for w: WeaponData in WeaponCatalog.all():
		if w.unlock_mode == WeaponData.UNLOCK_KILL and not out.has(w.unlock_enemy_kind):
			out.append(w.unlock_enemy_kind)
	return out


## Encart de fin de raid : kills du raid qui comptent pour un déblocage.
## [{kind, name, count (ce raid), total, weapons: [{id, name, needed, done}]}]
static func kill_report(raid_kills: Dictionary, total_kills: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: StringName in unlock_kinds():
		var n := int(raid_kills.get(String(kind), 0))
		if n <= 0:
			continue
		var tot := int(total_kills.get(String(kind), 0))
		var ws: Array = []
		for w: WeaponData in weapons_unlocked_by(kind):
			ws.append({"id": w.id, "name": w.display_name, "needed": maxi(w.unlock_kills, 1), "done": tot >= maxi(w.unlock_kills, 1)})
		out.append({"kind": kind, "name": enemy_name(kind), "count": n, "total": tot, "weapons": ws})
	return out


## Format « 1 250 » (espace fine des milliers).
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
