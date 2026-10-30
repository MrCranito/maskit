class_name LootRoller
extends RefCounted
## Tirages de butin (logique pure, déterministe pour un RNG donné).
## Poids final d'un objet = poids de base (table) × multiplicateur de sa rareté :
##   × (1 + rarity_difficulty_bonus[r] × difficulté)
##   × (1 + rarity_floor_bonus[r] × |étage|)
##   × super_loot_rarity_mult[r]   (salle super_loot uniquement)
##   × (1 + loot_rarity_bonus_weights[r] × map_rarity_bonus)   (carte jouée, [maps])
## Les tableaux sont indexés par rareté (0 Commun … 4 Légendaire), cf. [loot].
## Nombre d'objets × map_quantity_mult (carte jouée ; chance de conteneur vide ÷ ce facteur).
## Les armes tirées reçoivent leurs affixes aléatoires (Affixes.roll_item, phase 8).

const ROOM_SUPER_LOOT := &"super_loot"

## Bonus de la carte en cours (MapCard : loot_rarity_bonus / loot_quantity_mult), fixés par
## Raid au lancement. Valeurs neutres (0 / 1) = comportement d'origine, tirages inchangés.
static var map_rarity_bonus: float = 0.0
static var map_quantity_mult: float = 1.0


## Remet les bonus de carte à leurs valeurs neutres.
static func reset_map_bonus() -> void:
	map_rarity_bonus = 0.0
	map_quantity_mult = 1.0


class Context:
	var difficulty: int = 1
	var floor_index: int = 0
	var room_type: StringName = &"combat"

	static func make(p_difficulty: int, p_floor: int, p_room_type: StringName) -> Context:
		var c := Context.new()
		c.difficulty = p_difficulty
		c.floor_index = p_floor
		c.room_type = p_room_type
		return c


static func rarity_multiplier(rarity: int, ctx: Context) -> float:
	var m := 1.0
	m *= 1.0 + LootDB.arr_at("rarity_difficulty_bonus", rarity, [0.0, 0.05, 0.15, 0.3, 0.45]) * float(ctx.difficulty)
	m *= 1.0 + LootDB.arr_at("rarity_floor_bonus", rarity, [0.0, 0.05, 0.2, 0.35, 0.5]) * float(absi(ctx.floor_index))
	if ctx.room_type == ROOM_SUPER_LOOT:
		m *= LootDB.arr_at("super_loot_rarity_mult", rarity, [0.3, 0.7, 2.0, 6.0, 10.0])
	if map_rarity_bonus != 0.0:
		var w: Variant = Balance.get_value("maps", "loot_rarity_bonus_weights", [0.0, 0.3, 0.7, 1.2, 1.6])
		var arr: Array = w if w is Array else []
		var k: float = float(arr[clampi(rarity, 0, arr.size() - 1)]) if not arr.is_empty() else 0.0
		m *= maxf(1.0 + k * map_rarity_bonus, 0.0)
	return maxf(m, 0.0)


## Poids effectifs {item_id: poids} de la table dans ce contexte (ids inconnus ignorés).
static func effective_weights(table: LootTable, ctx: Context) -> Dictionary:
	var out := {}
	for k: Variant in table.entries:
		var id := StringName(k)
		var it := LootDB.get_item(id)
		if it == null:
			continue
		var w := float(table.entries[k]) * rarity_multiplier(it.rarity, ctx)
		if w > 0.0:
			out[id] = w
	return out


## Tire le contenu d'un conteneur : Array de {"item": ItemData, "count": int}.
## Objets distincts (pas deux fois le même), triés par rareté décroissante.
static func roll(table: LootTable, rng: RandomNumberGenerator, ctx: Context) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if table == null:
		return out
	var super_loot := ctx.room_type == ROOM_SUPER_LOOT
	var empty := 0.0 if super_loot else table.empty_chance
	if map_quantity_mult > 1.0:
		empty /= map_quantity_mult
	if rng.randf() < empty:
		return out
	var n := rng.randi_range(table.rolls_min, maxi(table.rolls_min, table.rolls_max))
	if super_loot:
		n += LootDB.geti("super_loot_extra_rolls", 1)
	if map_quantity_mult != 1.0:
		n = maxi(1, roundi(n * maxf(map_quantity_mult, 0.0)))
	var weights := effective_weights(table, ctx)
	for i in n:
		if weights.is_empty():
			break
		var id := pick_weighted(weights, rng)
		weights.erase(id)
		var it := LootDB.get_item(id)
		var count := rng.randi_range(maxi(it.drop_min, 1), maxi(it.drop_max, it.drop_min))
		# Arme : affixes tirés au drop (RNG dérivé, ne décale pas le reste du tirage).
		out.append({"item": Affixes.roll_item(it, rng), "count": mini(count, maxi(it.stack_max, 1) * 4)})
	sort_entries(out)
	return out


static func sort_entries(entries: Array[Dictionary]) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia: ItemData = a["item"]
		var ib: ItemData = b["item"]
		if ia.rarity != ib.rarity:
			return ia.rarity > ib.rarity
		return String(ia.id) < String(ib.id))


## Tirage pondéré déterministe (clés triées, indépendant de l'ordre du dictionnaire).
static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var keys: Array = weights.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var total := 0.0
	for k: Variant in keys:
		total += float(weights[k])
	var r := rng.randf() * total
	for k2: Variant in keys:
		r -= float(weights[k2])
		if r <= 0.0:
			return StringName(k2)
	return StringName(keys[keys.size() - 1])


## Meilleure rareté d'un contenu (-1 si vide).
static func best_rarity(entries: Array) -> int:
	var best := -1
	for e: Dictionary in entries:
		best = maxi(best, (e["item"] as ItemData).rarity)
	return best


static func total_value(entries: Array) -> int:
	var v := 0
	for e: Dictionary in entries:
		v += (e["item"] as ItemData).value * int(e["count"])
	return v


## Seed stable d'un conteneur (même raid → même contenu).
static func container_seed(run_seed: int, floor_index: int, cell: Vector2i, kind: StringName) -> int:
	return hash([run_seed, floor_index, cell.x, cell.y, String(kind), "loot"])
