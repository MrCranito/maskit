class_name ItemUse
extends RefCounted
## Actions sur un objet du sac de raid, partagées par l'écran d'inventaire, les emplacements
## rapides du HUD et les touches quick_1..n (clavier, plus tard manette) :
##   - utiliser un consommable (soin) ;
##   - équiper une arme (emplacement courant) ou un équipement (emplacement d'équipement) :
##     l'objet quitte le sac, l'arme remplacée y revient ;
##   - emplacement rapide : consommable → utilisé ; équipement → équipé.
## Chaque fonction renvoie "" en cas de succès, sinon un message court pour le joueur.
## API joueur interrogée via has_method (contrat Exfil Rush, faux joueurs des tests).


## Utilise une unité de la case `slot_idx` (consommable de soin).
static func use_slot(inv: Inventory, slot_idx: int, p: Node) -> String:
	if inv == null:
		return "Sac indisponible."
	var it := inv.get_slot(slot_idx).get("item") as ItemData
	if it == null or not it.is_usable():
		return "Cet objet ne s'utilise pas."
	if p == null or not is_instance_valid(p) or not p.has_method(&"heal"):
		return "Impossible pour l'instant."
	var hp: Variant = p.get("hp")
	var max_hp: Variant = p.get("max_hp")
	if hp != null and max_hp != null and float(hp) >= float(max_hp):
		return "PV déjà au maximum."
	p.call(&"heal", it.heal_amount)
	inv.remove_at(slot_idx, 1)
	return ""


## Équipe l'arme ou l'équipement de la case `slot_idx`. `weapon_slot` >= 0 : l'arme va dans cet
## emplacement (le joueur y bascule d'abord), sinon dans l'emplacement courant.
static func equip_slot(inv: Inventory, slot_idx: int, p: Node, weapon_slot: int = -1) -> String:
	if inv == null:
		return "Sac indisponible."
	var it := inv.get_slot(slot_idx).get("item") as ItemData
	if it == null or not it.is_weapon() or p == null or not is_instance_valid(p):
		return "Impossible d'équiper cet objet."
	# Exemplaire avec ses affixes ; l'arme remplacée revient dans le sac avec les siens.
	var w := it.get_weapon()
	if w == null:
		return "Impossible d'équiper cet objet."
	var method: StringName = &"equip_gadget" if w.is_gadget() else &"equip_into_current_slot"
	if not p.has_method(method):
		return "Impossible d'équiper cet objet pour l'instant."
	if not w.is_gadget() and weapon_slot >= 0 and p.has_method(&"switch_to"):
		var cur: Variant = p.get("current_slot")
		if not (cur is int and int(cur) == weapon_slot):
			p.call(&"switch_to", weapon_slot)
	var current: WeaponData = null
	if w.is_gadget():
		current = p.call(&"get_gadget") as WeaponData if p.has_method(&"get_gadget") else null
	else:
		current = p.get("weapon") as WeaponData
	var removed := inv.remove_at(slot_idx, 1)
	if removed.is_empty():
		return "Impossible d'équiper cet objet."
	# Place pour l'objet remplacé vérifiée AVANT l'échange (le sac a libéré une case).
	var slot_empty := false if w.is_gadget() else current_slot_empty(p)
	if current != null and not slot_empty:
		var back_item := LootDB.weapon_item(current)
		if back_item != null and not inv.can_add(back_item, 1):
			# Remet l'objet exactement dans sa case (pas de nouvelle vérification de poids).
			if inv.slots[slot_idx] == null:
				inv.slots[slot_idx] = removed
			else:
				inv.slots[slot_idx]["count"] = int(inv.slots[slot_idx]["count"]) + int(removed["count"])
			inv.changed.emit()
			return "Sac plein : libère de la place pour ranger l'objet actuel."
	var replaced: Variant = p.call(method, w)
	if replaced is WeaponData:
		var bi := LootDB.weapon_item(replaced as WeaponData)
		if bi != null:
			inv.add_item(bi, 1)
	return ""


## Emplacement rapide `i` : consommable utilisé, équipement équipé.
static func use_quick(inv: Inventory, i: int, p: Node) -> String:
	if inv == null or i < 0 or i >= inv.quick_count():
		return "Emplacement rapide indisponible."
	if inv.quick[i].is_empty():
		return "Emplacement rapide vide : glisse un objet depuis le sac."
	var at := inv.find_slot(inv.quick[i])
	if at < 0:
		return "Plus aucun exemplaire dans le sac."
	var it := inv.get_slot(at)["item"] as ItemData
	if it.is_usable():
		return use_slot(inv, at, p)
	return equip_slot(inv, at, p)


static func current_slot_empty(p: Node) -> bool:
	if not p.has_method(&"get_weapons"):
		return false
	var list: Variant = p.call(&"get_weapons")
	var idx: Variant = p.get("current_slot")
	if list is Array and idx is int:
		var arr: Array = list
		return int(idx) >= arr.size() or arr[int(idx)] == null
	return false


static func play(node: Node, sfx: StringName) -> void:
	if node == null or not node.is_inside_tree():
		return
	var am := node.get_tree().root.get_node_or_null(^"AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx)
