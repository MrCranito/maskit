class_name Affixes
extends RefCounted
## Affixes d'armes tirés au hasard à chaque drop (phase 8, décision du 30/10) : catalogue
## (data/affixes/*.tres), tirage, et exemplaires d'armes / objets de sac qui les portent.
##
## Règles :
##  - nombre d'affixes selon la rareté du modèle ([affixes] count_min / count_max, indexés par
##    rareté 0..4) ; jamais deux fois le même ; tirage pondéré (AffixData.weight), reproductible
##    avec le RNG passé en paramètre ;
##  - tirage uniquement quand une arme TOMBE en raid (LootRoller.roll, butin au sol des ennemis) ;
##    armurerie, artisanat, arme de départ, récompenses : aucun affixe ;
##  - un exemplaire = un WeaponData DUPLIQUÉ (rolled_affixes rempli, multi-tir appliqué aux stats)
##    et, dans le sac, un ItemData dupliqué (weapon_affixes). Les ressources du catalogue ne sont
##    jamais modifiées. Les exemplaires identiques (même modèle, mêmes affixes) sont partagés (cache).
##  - un affixe augmente la valeur marchande : × (1 + value_bonus_per_affix × n).

const DIR := "res://data/affixes/"
const SECTION := "affixes"

static var _cache: Dictionary = {}
static var _loaded: bool = false
## Clé d'exemplaire → WeaponData / ItemData (identité stable : cartes d'UI, sac, butin au sol).
static var _weapons: Dictionary = {}
static var _items: Dictionary = {}


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for f: String in LootDB._list_resources(DIR):
		var a := load(DIR + f) as AffixData
		if a == null:
			push_warning("Affixes: affixe illisible %s" % f)
			continue
		if String(a.id).is_empty():
			a.id = StringName(f.get_basename())
		_cache[a.id] = a


static func reload() -> void:
	_loaded = false
	_cache.clear()
	_weapons.clear()
	_items.clear()
	_load_all()


static func get_affix(id: StringName) -> AffixData:
	_load_all()
	return _cache.get(id) as AffixData


static func has_affix(id: StringName) -> bool:
	_load_all()
	return _cache.has(id)


## Tous les affixes, triés par id.
static func all() -> Array[AffixData]:
	_load_all()
	var keys: Array = _cache.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var out: Array[AffixData] = []
	for k: Variant in keys:
		out.append(_cache[k])
	return out


# --- Réglages [affixes] ----------------------------------------------------------------

static func enabled() -> bool:
	return bool(Balance.get_value(SECTION, "enabled", true))


static func _arr_at(key: String, index: int, def: Array) -> int:
	var v: Variant = Balance.get_value(SECTION, key, def)
	var a: Array = v if v is Array and not (v as Array).is_empty() else def
	return int(a[clampi(index, 0, a.size() - 1)])


## Nombre d'affixes (min, max) d'une arme de cette rareté.
static func count_range(rarity: int) -> Vector2i:
	var lo := maxi(_arr_at("count_min", rarity, [0, 0, 1, 1, 2]), 0)
	var hi := maxi(_arr_at("count_max", rarity, [0, 0, 1, 2, 2]), lo)
	return Vector2i(lo, hi)


## Multiplicateur de valeur marchande pour n affixes.
static func value_mult(n: int) -> float:
	return 1.0 + float(Balance.get_value(SECTION, "value_bonus_per_affix", 0.15)) * float(maxi(n, 0))


# --- Tirage ------------------------------------------------------------------------------

## Affixes tirés pour un exemplaire de `w` (ids triés, sans doublon). Logique pure.
static func roll_for(w: WeaponData, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	if w == null or w.is_gadget() or rng == null or not enabled():
		return out
	var r := count_range(w.rarity)
	if r.y <= 0:
		return out
	var n := rng.randi_range(r.x, r.y) if r.y > r.x else r.x
	var weights := {}
	for a: AffixData in all():
		if a.allows(w):
			weights[a.id] = a.weight
	for i in n:
		if weights.is_empty():
			break
		var id := LootRoller.pick_weighted(weights, rng)
		weights.erase(id)
		out.append(id)
	_sort_ids(out)
	return out


## Objet tombé en raid : une arme reçoit ses affixes (objet dupliqué), le reste est rendu tel quel.
## Le tirage utilise un RNG DÉRIVÉ de l'état de `rng` (sans le faire avancer) : le reste du
## butin d'un conteneur reste identique à avant les affixes, et le même conteneur donne les
## mêmes affixes (coop : l'invité retire le même contenu).
static func roll_item(it: ItemData, rng: RandomNumberGenerator) -> ItemData:
	if it == null or not it.is_weapon() or not it.weapon_affixes.is_empty() or rng == null:
		return it
	var w := WeaponCatalog.get_weapon(it.weapon_id)
	if w == null or count_range(w.rarity).y <= 0:
		return it
	var arng := RandomNumberGenerator.new()
	arng.seed = hash([rng.state, String(it.id), "affixes"])
	var ids := roll_for(w, arng)
	return make_item(it, ids) if not ids.is_empty() else it


# --- Exemplaires -------------------------------------------------------------------------

## Ids connus, sans doublon, triés.
static func normalized(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v: Variant in ids:
		var id := StringName(str(v))
		if has_affix(id) and not out.has(id):
			out.append(id)
	_sort_ids(out)
	return out


## Tri alphabétique (Array.sort() ne trie pas les StringName par ordre alphabétique).
static func _sort_ids(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


## Clé d'exemplaire : l'id du modèle seul s'il n'a pas d'affixe (« rifle_ak47 »), sinon
## « rifle_ak47+burn,freeze ».
static func key_for(id: StringName, ids: Array) -> String:
	var n := normalized(ids)
	if n.is_empty():
		return String(id)
	var parts := PackedStringArray()
	for s: StringName in n:
		parts.append(String(s))
	return "%s+%s" % [String(id), ",".join(parts)]


static func key_of(w: WeaponData) -> String:
	return key_for(w.id, w.rolled_affixes) if w != null else ""


## Exemplaire de `base` portant `ids` (base elle-même si aucun affixe). Jamais de modification
## de la ressource du catalogue. Multi-tir : projectiles et éventail ajoutés aux stats.
static func make_weapon(base: WeaponData, ids: Array) -> WeaponData:
	if base == null:
		return null
	var n := normalized(ids)
	if n.is_empty():
		return base
	var key := key_for(base.id, n)
	var cached: WeaponData = _weapons.get(key) as WeaponData
	if cached != null:
		return cached
	var w := base.duplicate() as WeaponData
	w.affixes = base.affixes.duplicate()
	w.rolled_affixes = n
	w.value = roundi(float(base.value) * value_mult(n.size()))
	for id: StringName in n:
		var a := get_affix(id)
		if a != null and a.kind == AffixData.KIND_MULTISHOT:
			w.projectile_count = maxi(w.projectile_count, 1) + maxi(a.count, 0)
			w.spread_degrees = maxf(w.spread_degrees, 0.0) + a.spread_deg
	_weapons[key] = w
	return w


## Objet de sac portant `ids` (base_item lui-même si aucun affixe), valeur augmentée.
static func make_item(base_item: ItemData, ids: Array) -> ItemData:
	if base_item == null:
		return null
	var n := normalized(ids)
	if n.is_empty() or not base_item.is_weapon():
		return base_item
	var key := key_for(base_item.weapon_id, n)
	var cached: ItemData = _items.get(key) as ItemData
	if cached != null:
		return cached
	var it := base_item.duplicate() as ItemData
	it.weapon_affixes = n
	it.value = roundi(float(base_item.value) * value_mult(n.size()))
	_items[key] = it
	return it


## Affixes résolus (ressources) d'une liste d'ids, ordre conservé.
static func resolve(ids: Array) -> Array[AffixData]:
	var out: Array[AffixData] = []
	for v: Variant in ids:
		var a := get_affix(StringName(str(v)))
		if a != null:
			out.append(a)
	return out


## Noms affichés (« Brûlure, Gel »).
static func names_text(ids: Array, sep: String = ", ") -> String:
	var parts := PackedStringArray()
	for a: AffixData in resolve(ids):
		parts.append(a.display_name)
	return sep.join(parts)
