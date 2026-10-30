class_name DropCaps
extends RefCounted
## Plafonds de taux de drop par fouille ([loot] drop_cap_epic / drop_cap_legendary) et sources
## exemptées. Référence partagée avec tools/cap_drop_rates.py (qui baisse les poids des tables).
## Les cadavres de boss (EnemyData.boss = true) sont exemptés si [loot] drop_cap_exempt_bosses :
## leur table tire 4 à 6 objets sans remise et doit vraiment payer.

const ENEMY_DIR := "res://data/enemies/"


## Plafond d'une rareté (chance max par fouille), -1 si la rareté n'est pas plafonnée.
static func cap_for_rarity(rarity: int) -> float:
	if rarity >= 4:
		return LootDB.getf("drop_cap_legendary", 0.01)
	if rarity == 3:
		return LootDB.getf("drop_cap_epic", 0.04)
	return -1.0


static func bosses_exempt() -> bool:
	return bool(LootDB.cfg().get_value(LootDB.SECTION, "drop_cap_exempt_bosses", true))


## Table propre d'un archétype (data.loot_table, sinon enemy_<kind>) ; &"" s'il n'en a pas
## (il retombe alors sur la table de son biome, partagée, jamais exemptée).
static func own_table_kind(data: EnemyData) -> StringName:
	if data == null:
		return &""
	if data.loot_table != &"" and LootDB.get_table(data.loot_table) != null:
		return data.loot_table
	var k := StringName("enemy_" + String(data.kind))
	return k if LootDB.get_table(k) != null else &""


## Archétypes boss (data/enemies, EnemyData.boss = true).
static func boss_datas() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for f: String in LootDB._list_resources(ENEMY_DIR):
		var data := load(ENEMY_DIR + f) as EnemyData
		if data != null and data.boss:
			out.append(data)
	return out


## Tables propres des boss, sans doublon.
static func boss_table_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for data: EnemyData in boss_datas():
		var k := own_table_kind(data)
		if k != &"" and not out.has(k):
			out.append(k)
	return out


## La table `kind` est-elle exemptée du plafond ?
static func is_exempt(kind: StringName) -> bool:
	return bosses_exempt() and boss_table_kinds().has(kind)


## Chance plafonnée pour un objet de cette rareté dans cette table (-1 = pas de plafond).
static func cap_for(table_kind: StringName, rarity: int) -> float:
	if is_exempt(table_kind):
		return -1.0
	return cap_for_rarity(rarity)
