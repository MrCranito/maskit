class_name HatchKeys
extends RefCounted
## Clef de trappe d'urgence : objet `hatch_key` (sac de raid) et gadget `gadget_hatch_key`
## (emplacement d'équipement, emporté depuis l'arsenal).
##   - drop : au sol sur les ennemis (hatch_key_enemy_chance par difficulté, × élite) et à la
##     fouille des coffres (hatch_key_container_chance par type) — [extraction] de balance.cfg ;
##   - ouverture d'une trappe : consomme d'abord une clef du sac, sinon la charge du gadget ;
##   - extraction : une clef du sac rejoint la réserve sous forme de gadget (ItemData.weapon_id),
##     le gadget non utilisé revient comme tout équipement chargé ; mort : tout est perdu.

const ITEM_ID := &"hatch_key"
const GADGET_ID := &"gadget_hatch_key"


## Clefs disponibles : sac + gadget chargé.
static func count(inv: Inventory, player: Node) -> int:
	var n := inv.count_of(ITEM_ID) if inv != null else 0
	if player != null and player.has_method(&"has_hatch_key_gadget") and bool(player.call(&"has_hatch_key_gadget")):
		n += 1
	return n


## Consomme une clef : « bag », « gadget » ou « » (aucune).
static func consume(inv: Inventory, player: Node) -> String:
	if inv != null and inv.has_item(ITEM_ID):
		inv.remove_item(ITEM_ID, 1)
		return "bag"
	if player != null and player.has_method(&"consume_hatch_key_gadget") and bool(player.call(&"consume_hatch_key_gadget")):
		return "gadget"
	return ""


## Chance de drop sur un ennemi tué (difficulté 0..4, élite).
static func enemy_chance(difficulty: int, elite: bool) -> float:
	var arr: Variant = Balance.get_value("extraction", "hatch_key_enemy_chance", [0.008, 0.01, 0.012, 0.014, 0.016])
	var c := 0.0
	if arr is Array and not (arr as Array).is_empty():
		c = float(arr[clampi(difficulty, 0, (arr as Array).size() - 1)])
	if elite:
		c *= Balance.get_float("extraction", "hatch_key_elite_mult", 4.0)
	return c


## Chance à la fouille d'un conteneur de type `kind` (0 si absent de la table).
static func container_chance(kind: StringName) -> float:
	var d: Variant = Balance.get_value("extraction", "hatch_key_container_chance", {})
	return float((d as Dictionary).get(String(kind), 0.0)) if d is Dictionary else 0.0


## Tirage indépendant (graine propre : ne décale pas les autres tirages). Renvoie une entrée
## de butin {"item", "count"} ou {}.
static func roll(seed_value: int, chance: float) -> Dictionary:
	if chance <= 0.0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "hatch_key"])
	if rng.randf() >= chance:
		return {}
	var it := LootDB.get_item(ITEM_ID)
	return {"item": it, "count": 1} if it != null else {}
