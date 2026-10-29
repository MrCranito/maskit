class_name Inventory
extends RefCounted
## Inventaire de raid : grille de `columns` × `rows` cases, chaque case contient
## une pile d'un seul objet (≤ stack_max), plus un poids maximal (kg).
## Logique pure (aucun nœud) : GameState.raid_inventory en garde une instance.
## Toute modification émet `changed` (l'UI ne se redessine qu'à ce moment-là).

signal changed
## Émis quand un objet entre (après fusion dans les piles) : utile pour les toasts / sons.
signal item_added(item: ItemData, count: int)
signal item_removed(item: ItemData, count: int)

var columns: int = 6
var rows: int = 4
var max_weight: float = 30.0
## Une entrée par case : null ou {"item": ItemData, "count": int}.
var slots: Array = []


func _init(p_columns: int = 6, p_rows: int = 4, p_max_weight: float = 30.0) -> void:
	columns = maxi(p_columns, 1)
	rows = maxi(p_rows, 1)
	max_weight = p_max_weight
	slots.resize(columns * rows)
	slots.fill(null)


## Inventaire aux dimensions de [loot] (balance.cfg) ; poids max + bonus du niveau de raider.
static func from_balance() -> Inventory:
	return Inventory.new(LootDB.geti("inventory_columns", 6), LootDB.geti("inventory_rows", 4),
		LootDB.getf("inventory_max_weight", 30.0) + RaiderProgress.bag_bonus_at(RaiderProgress.current_level()))


func capacity() -> int:
	return slots.size()


func get_slot(i: int) -> Dictionary:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return {}
	return slots[i]


func is_empty() -> bool:
	for s: Variant in slots:
		if s != null:
			return false
	return true


func used_slots() -> int:
	var n := 0
	for s: Variant in slots:
		if s != null:
			n += 1
	return n


func total_weight() -> float:
	var w := 0.0
	for s: Variant in slots:
		if s != null:
			w += (s["item"] as ItemData).weight * int(s["count"])
	return w


func total_value() -> int:
	var v := 0
	for s: Variant in slots:
		if s != null:
			v += (s["item"] as ItemData).value * int(s["count"])
	return v


func count_of(id: StringName) -> int:
	var n := 0
	for s: Variant in slots:
		if s != null and (s["item"] as ItemData).id == id:
			n += int(s["count"])
	return n


func has_item(id: StringName) -> bool:
	return count_of(id) > 0


## Combien d'unités de `item` peuvent entrer (places + poids).
func space_for(item: ItemData) -> int:
	if item == null:
		return 0
	var stack := maxi(item.stack_max, 1)
	var by_slots := 0
	for s: Variant in slots:
		if s == null:
			by_slots += stack
		elif (s["item"] as ItemData).id == item.id:
			by_slots += maxi(stack - int(s["count"]), 0)
	if item.weight <= 0.0:
		return by_slots
	var by_weight := int(floor((max_weight - total_weight()) / item.weight + 0.0001))
	return clampi(mini(by_slots, by_weight), 0, by_slots)


func can_add(item: ItemData, count: int = 1) -> bool:
	return space_for(item) >= count


## Ajoute jusqu'à `count` unités (complète d'abord les piles existantes).
## Renvoie le nombre réellement ajouté (0 si plein / trop lourd).
func add_item(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var todo := mini(count, space_for(item))
	if todo <= 0:
		return 0
	var stack := maxi(item.stack_max, 1)
	var left := todo
	for i in slots.size():
		if left <= 0:
			break
		var s: Variant = slots[i]
		if s != null and (s["item"] as ItemData).id == item.id and int(s["count"]) < stack:
			var put := mini(stack - int(s["count"]), left)
			s["count"] = int(s["count"]) + put
			left -= put
	for j in slots.size():
		if left <= 0:
			break
		if slots[j] == null:
			var put2 := mini(stack, left)
			slots[j] = {"item": item, "count": put2}
			left -= put2
	var added := todo - left
	if added > 0:
		item_added.emit(item, added)
		changed.emit()
	return added


## Retire jusqu'à `count` unités de l'objet `id` (piles de fin de grille d'abord).
## Renvoie le nombre retiré.
func remove_item(id: StringName, count: int = 1) -> int:
	var left := count
	var item: ItemData = null
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var s: Variant = slots[i]
		if s == null or (s["item"] as ItemData).id != id:
			continue
		item = s["item"]
		var take := mini(int(s["count"]), left)
		s["count"] = int(s["count"]) - take
		left -= take
		if int(s["count"]) <= 0:
			slots[i] = null
	var removed := count - left
	if removed > 0:
		item_removed.emit(item, removed)
		changed.emit()
	return removed


## Retire `count` unités (toutes si -1) de la case `i`. Renvoie {"item", "count"} retirés ({} si vide).
func remove_at(i: int, count: int = -1) -> Dictionary:
	var s := get_slot(i)
	if s.is_empty():
		return {}
	var take := int(s["count"]) if count < 0 else mini(count, int(s["count"]))
	s["count"] = int(s["count"]) - take
	if int(s["count"]) <= 0:
		slots[i] = null
	item_removed.emit(s["item"], take)
	changed.emit()
	return {"item": s["item"], "count": take}


## Regroupe les piles et trie : rareté décroissante, puis type, puis nom.
func sort() -> void:
	var totals := {}
	var items := {}
	for s: Variant in slots:
		if s == null:
			continue
		var it: ItemData = s["item"]
		totals[it.id] = int(totals.get(it.id, 0)) + int(s["count"])
		items[it.id] = it
	var ids: Array = items.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ia: ItemData = items[a]
		var ib: ItemData = items[b]
		if ia.rarity != ib.rarity:
			return ia.rarity > ib.rarity
		if ia.type != ib.type:
			return String(ia.type) < String(ib.type)
		return ia.display_name < ib.display_name)
	slots.fill(null)
	var idx := 0
	for id: Variant in ids:
		var it2: ItemData = items[id]
		var n := int(totals[id])
		var stack := maxi(it2.stack_max, 1)
		while n > 0 and idx < slots.size():
			var put := mini(stack, n)
			slots[idx] = {"item": it2, "count": put}
			n -= put
			idx += 1
	changed.emit()


func clear() -> void:
	slots.fill(null)
	changed.emit()


## Sérialisation (sauvegarde / transfert vers la réserve) : [[id, count], …] par case.
func to_array() -> Array:
	var out: Array = []
	for s: Variant in slots:
		out.append(null if s == null else [String((s["item"] as ItemData).id), int(s["count"])])
	return out


func from_array(data: Array) -> void:
	slots.fill(null)
	for i in mini(data.size(), slots.size()):
		var e: Variant = data[i]
		if e is Array and (e as Array).size() >= 2:
			var it := LootDB.get_item(StringName(e[0]))
			if it != null:
				slots[i] = {"item": it, "count": int(e[1])}
	changed.emit()
