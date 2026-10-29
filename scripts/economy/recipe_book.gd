class_name RecipeBook
extends RefCounted
## Recettes d'artisanat (data/recipes/*.tres, RecipeData), chargées une fois et mises en cache,
## + logique pure (sans autoload Profile) : disponibilité des ingrédients dans un stock
## {id d'objet: quantité}, plan de consommation, recettes utilisant un objet.
## Groupes d'ingrédients « @nom » : balance.cfg [crafting] group_<nom> = [ids…].

const DIR := "res://data/recipes/"
const SECTION := "crafting"
## Noms affichés des groupes d'ingrédients.
const GROUP_NAMES := {
	"mechanism": "Mécanisme",
	"scrap": "Ferraille",
}

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for f: String in LootDB._list_resources(DIR):
		var r := load(DIR + f) as RecipeData
		if r == null:
			push_warning("RecipeBook: recette illisible %s" % f)
			continue
		if String(r.id).is_empty():
			r.id = StringName(f.get_basename())
		_apply_cost(r)
		_cache[r.id] = r


## Coût en or effectif (balance [crafting] gold_cost_mult, min_gold_cost) écrit dans
## r.gold_cost : Profile.craft et l'écran de l'atelier lisent directement ce champ. La valeur du
## .tres est gardée en méta (base_gold_cost) pour ne jamais multiplier deux fois (reload).
static func _apply_cost(r: RecipeData) -> void:
	if not r.has_meta(&"base_gold_cost"):
		r.set_meta(&"base_gold_cost", r.gold_cost)
	r.gold_cost = cost_of(int(r.get_meta(&"base_gold_cost")))


## Coût effectif d'une valeur de base (.tres).
static func cost_of(base: int) -> int:
	var mult := float(_balance(SECTION, "gold_cost_mult", 1.0))
	var mn := int(_balance(SECTION, "min_gold_cost", 5))
	return maxi(int(round(float(maxi(base, 0)) * mult)), mn)


## Raison du refus d'une fabrication ("" = possible) : ingrédients manquants d'abord,
## puis « Il te manque 35 or ».
static func refusal(r: RecipeData, stock: Dictionary, gold: int) -> String:
	if r == null or not _result_valid(r):
		return "Recette inconnue"
	var miss := missing(r, stock)
	if not miss.is_empty():
		var parts: PackedStringArray = []
		for k: Variant in miss:
			parts.append("%d %s" % [int(miss[k]), key_name(str(k)).to_lower()])
		return "Manque : " + ", ".join(parts)
	if gold < r.gold_cost:
		return "Il te manque %d or" % (r.gold_cost - gold)
	return ""


static func reload() -> void:
	_loaded = false
	_cache.clear()
	_load_all()


static func get_recipe(id: StringName) -> RecipeData:
	_load_all()
	return _cache.get(id) as RecipeData


## Toutes les recettes, triées (sort_order puis id).
static func all() -> Array[RecipeData]:
	_load_all()
	var out: Array[RecipeData] = []
	for r: RecipeData in _cache.values():
		out.append(r)
	out.sort_custom(func(a: RecipeData, b: RecipeData) -> bool:
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else String(a.id) < String(b.id))
	return out


# --- Groupes ------------------------------------------------------------------------

static func is_group(key: String) -> bool:
	return key.begins_with("@")


## Ids d'objets acceptés pour une clé d'ingrédient (id simple ou « @groupe »).
static func options_for(key: String) -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_group(key):
		out.append(StringName(key))
		return out
	var v: Variant = _balance(SECTION, "group_" + key.substr(1), [])
	if v is Array:
		for id: Variant in v:
			if LootDB.has_item(StringName(str(id))):
				out.append(StringName(str(id)))
	return out


## Nom affiché d'une clé d'ingrédient.
static func key_name(key: String) -> String:
	if is_group(key):
		return String(GROUP_NAMES.get(key.substr(1), key.substr(1).capitalize()))
	var it := LootDB.get_item(StringName(key))
	return it.display_name if it != null else key


## Détail d'un groupe pour l'affichage : « rouages, circuits, piles… ».
static func group_hint(key: String) -> String:
	var names: PackedStringArray = []
	for id: StringName in options_for(key):
		var it := LootDB.get_item(id)
		if it != null:
			names.append(it.display_name.to_lower())
	return ", ".join(names)


## Objet représentatif d'une clé (icône) : le premier possédé, sinon le premier du groupe.
static func key_item(key: String, stock: Dictionary = {}) -> ItemData:
	var opts := options_for(key)
	for id: StringName in opts:
		if int(stock.get(String(id), 0)) > 0:
			return LootDB.get_item(id)
	return LootDB.get_item(opts[0]) if not opts.is_empty() else null


# --- Stock -------------------------------------------------------------------------------

## Quantité disponible pour une clé dans `stock` (id → n ; clés String ou StringName).
static func available(key: String, stock: Dictionary) -> int:
	var n := 0
	for id: StringName in options_for(key):
		n += _count(stock, id)
	return n


static func _count(stock: Dictionary, id: StringName) -> int:
	return int(stock.get(String(id), stock.get(id, 0)))


## Ingrédients manquants : {clé: quantité manquante} (vide = tout est là).
static func missing(r: RecipeData, stock: Dictionary) -> Dictionary:
	var out := {}
	if r == null:
		return out
	for k: Variant in r.ingredients:
		var need := int(r.ingredients[k])
		var have := available(str(k), stock)
		if have < need:
			out[str(k)] = need - have
	return out


static func can_craft(r: RecipeData, stock: Dictionary, gold: int) -> bool:
	return r != null and gold >= r.gold_cost and missing(r, stock).is_empty() and _result_valid(r)


## Nombre de fabrications possibles avec ce stock et cet or.
static func max_crafts(r: RecipeData, stock: Dictionary, gold: int) -> int:
	if r == null or not _result_valid(r):
		return 0
	var n := 999
	if r.gold_cost > 0:
		n = gold / r.gold_cost
	for k: Variant in r.ingredients:
		var need := maxi(int(r.ingredients[k]), 1)
		n = mini(n, available(str(k), stock) / need)
	return maxi(n, 0)


static func _result_valid(r: RecipeData) -> bool:
	if r.is_weapon_result():
		return WeaponCatalog.has_weapon(r.result_weapon_id)
	return LootDB.has_item(r.result_item_id)


## Plan de consommation {id d'objet: quantité} (vide si impossible). Dans un groupe, les
## objets les moins chers partent en premier (on garde ce qui se vend bien).
static func plan(r: RecipeData, stock: Dictionary) -> Dictionary:
	var out := {}
	if r == null or not missing(r, stock).is_empty():
		return out
	var left := stock.duplicate()
	for k: Variant in r.ingredients:
		var need := int(r.ingredients[k])
		var opts := options_for(str(k))
		opts.sort_custom(func(a: StringName, b: StringName) -> bool:
			var ia := LootDB.get_item(a)
			var ib := LootDB.get_item(b)
			var va := ia.value if ia != null else 0
			var vb := ib.value if ib != null else 0
			return va < vb if va != vb else String(a) < String(b))
		for id: StringName in opts:
			if need <= 0:
				break
			var have := _count(left, id) - int(out.get(String(id), 0))
			var take := mini(have, need)
			if take > 0:
				out[String(id)] = int(out.get(String(id), 0)) + take
				need -= take
		if need > 0:
			return {}
	return out


## Recettes qui utilisent cet objet (directement ou via un groupe).
static func recipes_using(item_id: StringName) -> Array[RecipeData]:
	var out: Array[RecipeData] = []
	for r: RecipeData in all():
		for k: Variant in r.ingredients:
			if options_for(str(k)).has(item_id):
				out.append(r)
				break
	return out


## « Bandages, Leurre » : noms des recettes utilisant cet objet ("" si aucune).
static func usage_text(item_id: StringName) -> String:
	var names: PackedStringArray = []
	for r: RecipeData in recipes_using(item_id):
		if not names.has(r.result_name()):
			names.append(r.result_name())
	return ", ".join(names)


static func _balance(section: String, key: String, def: Variant) -> Variant:
	var loop := Engine.get_main_loop() as SceneTree
	var b: Node = loop.root.get_node_or_null(^"Balance") if loop != null and loop.root != null else null
	if b != null:
		return b.call("get_value", section, key, def)
	return LootDB.cfg().get_value(section, key, def)
