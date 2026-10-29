class_name RaiderProgress
extends RefCounted
## Niveau de raider : progression PERMANENTE du joueur (ne se remet jamais à zéro), distincte du
## pass de combat (saisonnier, cosmétique). L'XP vient des fins de raid (même calcul que le pass,
## × [raider] xp_ratio) ; chaque niveau peut débloquer du gameplay.
## Données dans data/balance.cfg [raider] : courbe d'XP et liste `unlocks` de dictionnaires
## {level, kind, value?, label?} ; kinds :
##   loadout_slot : +1 emplacement d'arme (à partir de [raider] start_loadout_slots, plafonné par
##                  [arsenal] loadout_slots) ;
##   map          : la carte `value` (id MapCard) demande ce niveau ;
##   bag_weight   : +`value` kg au sac de raid ;
##   gems / gold  : `value` gemmes / or donnés une fois, au passage du niveau.
## L'XP est stockée dans Profile.raider_xp ; ce script ne garde aucun état.

const KIND_LOADOUT_SLOT := &"loadout_slot"
const KIND_MAP := &"map"
const KIND_BAG_WEIGHT := &"bag_weight"
const KIND_GEMS := &"gems"
const KIND_GOLD := &"gold"


static func max_level() -> int:
	return int(Balance.get_value("raider", "max_level", 30))


## XP à gagner pour passer du niveau `level` au suivant : base + pas × (niveau - 1).
static func xp_to_next(level: int) -> int:
	return int(Balance.get_value("raider", "xp_base", 400)) + int(Balance.get_value("raider", "xp_step", 150)) * maxi(level - 1, 0)


## XP totale pour atteindre `level` (niveau 1 = 0).
static func xp_total_for(level: int) -> int:
	var t := 0
	for l in range(1, clampi(level, 1, max_level())):
		t += xp_to_next(l)
	return t


## Niveau atteint avec `xp` d'XP cumulée.
static func level_for_xp(xp: int) -> int:
	var lv := 1
	var need := xp_to_next(1)
	var acc := 0
	while lv < max_level() and xp >= acc + need:
		acc += need
		lv += 1
		need = xp_to_next(lv)
	return lv


## Progression dans le niveau en cours : Vector2i(XP gagnée dans le niveau, XP nécessaire) ;
## (0, 0) au niveau maximal.
static func level_progress(xp: int) -> Vector2i:
	var lv := level_for_xp(xp)
	if lv >= max_level():
		return Vector2i.ZERO
	return Vector2i(xp - xp_total_for(lv), xp_to_next(lv))


## Liste des déblocages, triée par niveau.
static func unlocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in Balance.get_value("raider", "unlocks", []):
		if e is Dictionary and (e as Dictionary).has("level") and (e as Dictionary).has("kind"):
			var d: Dictionary = (e as Dictionary).duplicate()
			d["level"] = int(d["level"])
			d["kind"] = StringName(str(d["kind"]))
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) < int(b["level"]))
	return out


## Déblocages d'un niveau précis.
static func unlocks_at(level: int) -> Array[Dictionary]:
	return unlocks().filter(func(d: Dictionary) -> bool: return int(d["level"]) == level)


## Prochain déblocage après `level` (vide si aucun).
static func next_unlock(level: int) -> Dictionary:
	for d: Dictionary in unlocks():
		if int(d["level"]) > level:
			return d
	return {}


## Libellé lisible d'un déblocage (champ `label` prioritaire).
static func label_of(d: Dictionary) -> String:
	if d.has("label"):
		return str(d["label"])
	match StringName(str(d.get("kind", ""))):
		KIND_LOADOUT_SLOT:
			return "Emplacement d'arme supplémentaire"
		KIND_MAP:
			var c := MapCard.find(StringName(str(d.get("value", ""))))
			return ("Zone : " + c.display_name) if c != null else "Nouvelle zone"
		KIND_BAG_WEIGHT:
			return "Sac +%d kg" % int(d.get("value", 0))
		KIND_GEMS:
			return "%d gemmes" % int(d.get("value", 0))
		KIND_GOLD:
			return "%d or" % int(d.get("value", 0))
	return str(d.get("kind", ""))


## Catégorie lisible d'un déblocage (sous-titre).
static func kind_name(d: Dictionary) -> String:
	match StringName(str(d.get("kind", ""))):
		KIND_LOADOUT_SLOT:
			return "Arsenal de départ"
		KIND_MAP:
			return "Nouvelle zone"
		KIND_BAG_WEIGHT:
			return "Sac de raid"
		KIND_GEMS, KIND_GOLD:
			return "Récompense"
	return ""


## Niveau demandé par une carte (1 = libre).
static func required_level(map_id: StringName) -> int:
	for d: Dictionary in unlocks():
		if d["kind"] == KIND_MAP and StringName(str(d.get("value", ""))) == map_id:
			return int(d["level"])
	return 1


## Emplacements d'armes au niveau `level`.
static func loadout_slots_at(level: int) -> int:
	var n := int(Balance.get_value("raider", "start_loadout_slots", 2))
	for d: Dictionary in unlocks():
		if d["kind"] == KIND_LOADOUT_SLOT and int(d["level"]) <= level:
			n += 1
	return mini(n, int(Balance.get_value("arsenal", "loadout_slots", 3)))


## Bonus de poids du sac (kg) au niveau `level`.
static func bag_bonus_at(level: int) -> float:
	var kg := 0.0
	for d: Dictionary in unlocks():
		if d["kind"] == KIND_BAG_WEIGHT and int(d["level"]) <= level:
			kg += float(d.get("value", 0))
	return kg


## Niveau du profil actif (autoload Profile), 1 sans profil.
static func current_level() -> int:
	var p := _profile()
	return level_for_xp(int(p.get("raider_xp"))) if p != null else 1


## XP de raider d'une fin de raid, à partir de l'XP du pass (même barème) × [raider] xp_ratio.
static func raid_xp(pass_xp: int) -> int:
	return maxi(0, roundi(float(pass_xp) * float(Balance.get_value("raider", "xp_ratio", 1.0))))


## Ancienne sauvegarde sans niveau : XP de départ estimée à partir des statistiques
## (raids joués, extractions), pour ne pas retirer d'emplacement aux joueurs existants.
static func xp_from_stats(stats: Dictionary) -> int:
	return int(stats.get("raids", 0)) * int(Balance.get_value("raider", "legacy_xp_per_raid", 120)) \
		+ int(stats.get("extractions", 0)) * int(Balance.get_value("raider", "legacy_xp_per_extraction", 280))


static func _profile() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null(^"Profile") if loop != null and loop.root != null else null
