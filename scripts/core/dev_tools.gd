class_name DevTools
extends RefCounted
## Outils du mode développeur (DevMode), jamais disponibles en version publiée :
##  - build_profile() / build_battle_pass() : profil de développement « Tout débloquer », construit
##    en mémoire à partir du catalogue (aucune liste en dur) et des quantités [dev] de balance.cfg ;
##  - give_weapon() / give_item() : donner une arme ou un objet précis (raccourci du panneau F3, et
##    plus tard râtelier de l'arène de test). En raid : l'arme va dans la main du joueur (l'ancienne
##    passe dans le sac), l'objet dans le sac de raid ; hors raid : dans la réserve du profil.
## Tout passe par DevMode.is_available() : rien ne se fait dans un build publié.


## Profil complet à partir du profil réel `real` (Profile.to_dict()) : on garde l'apparence
## (skins portés), les réglages d'emport et les statistiques, tout le reste est débloqué.
static func build_profile(real: Dictionary = {}) -> Dictionary:
	var weapons: Array = []
	var uid := 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Balance.get_value("dev", "unlock_affix_seed", 1234))
	var affixed: int = int(Balance.get_value("dev", "unlock_affixed_copies", 1))
	var gadget_copies: int = maxi(1, int(Balance.get_value("dev", "unlock_gadget_copies", 3)))
	var ids_unlocked: Array = []
	for w: WeaponData in WeaponCatalog.all():
		ids_unlocked.append(String(w.id))
		var copies := gadget_copies if w.is_gadget() else 1
		for _k in copies:
			weapons.append({"uid": uid, "id": String(w.id), "affixes": []})
			uid += 1
		# Exemplaires à affixes (les affixes dépendent de la rareté du modèle : Communs souvent sans).
		if not w.is_gadget() and Affixes.enabled():
			for _k in affixed:
				var ax := Affixes.roll_for(w, rng)
				if ax.is_empty():
					continue
				var arr: Array = []
				for a: StringName in ax:
					arr.append(String(a))
				weapons.append({"uid": uid, "id": String(w.id), "affixes": arr})
				uid += 1
	var items := {}
	var n_items: int = int(Balance.get_value("dev", "unlock_item_count", 20))
	var n_keys: int = int(Balance.get_value("dev", "unlock_key_count", 5))
	for it: ItemData in LootDB.all_items():
		if it.is_weapon():
			continue
		items[String(it.id)] = n_keys if it.is_key() else n_items
	var skins: Array = []
	for k: StringName in [SkinData.KIND_CHARACTER, SkinData.KIND_WEAPON]:
		for s: SkinData in SkinData.all_of_kind(k):
			skins.append(String(s.id))
	var d := {
		"weapons": weapons,
		"loadout": [],
		"items": items,
		"gems": int(Balance.get_value("dev", "unlock_gems", 99999)),
		"gold": int(Balance.get_value("dev", "unlock_gold", 999999)),
		"unlocked_weapons": ids_unlocked,
		"skins_owned": skins,
		"raider_xp": RaiderProgress.xp_total_for(RaiderProgress.max_level()),
		"next_uid": uid,
	}
	for keep: String in ["skin_character", "skin_weapons", "stats", "pack_consumables", "pack_keys",
			"kills_by_kind", "bought_weapons", "shop_first_bonus_used", "bundles_bought"]:
		if real.has(keep):
			d[keep] = real[keep]
	return d


## Pass de combat complet : tous les paliers atteints, premium acheté, rien encore récupéré
## (chaque récompense reste récupérable pour la tester).
static func build_battle_pass(bp: BattlePassSystem) -> Dictionary:
	var s := bp.get_season()
	return {"season": String(s.id), "xp": s.xp_total_for(s.tiers), "premium": true, "claimed": []}


## Arsenal de départ maximal : les premières armes (meilleure rareté d'abord) + un équipement.
static func default_loadout(stash: Array[Dictionary], slots: int) -> Array[int]:
	var out: Array[int] = []
	var gadget := false
	for e: Dictionary in stash:
		var w: WeaponData = e["data"]
		if w.is_gadget():
			if not gadget:
				gadget = true
				out.append(int(e["uid"]))
		elif out.size() - (1 if gadget else 0) < slots:
			out.append(int(e["uid"]))
	return out


# --- Donner une arme ou un objet ------------------------------------------------------

## Catalogue du sélecteur : [{kind: &"weapon"|&"item", id, name, rarity}] trié (armes puis objets,
## rareté décroissante, nom).
static func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w: WeaponData in WeaponCatalog.all():
		out.append({"kind": &"weapon", "id": w.id, "name": w.display_name, "rarity": w.rarity})
	for it: ItemData in LootDB.all_items():
		if not it.is_weapon():
			out.append({"kind": &"item", "id": it.id, "name": it.display_name, "rarity": it.rarity})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["kind"] != b["kind"]:
			return a["kind"] == &"weapon"
		if int(a["rarity"]) != int(b["rarity"]):
			return int(a["rarity"]) > int(b["rarity"])
		return String(a["name"]) < String(b["name"]))
	return out


## Joueur du raid en cours (null hors raid).
static func raid_player() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return null
	var gs: Node = ml.root.get_node_or_null(^"GameState")
	var p: Variant = gs.get("player") if gs != null else null
	if p == null or not is_instance_valid(p) or not (p is Node):
		return null
	return p as Node if (p as Node).is_inside_tree() else null


## Donne l'arme `id`. En raid : en main (emplacement courant), l'arme remplacée part dans le sac.
## Hors raid : dans la réserve du profil. Renvoie un message court (affiché par le panneau), vide
## si refusé.
static func give_weapon(id: StringName, affixes: Array = []) -> String:
	if not DevMode.is_available():
		return ""
	var base := WeaponCatalog.get_weapon(id)
	if base == null:
		return ""
	var w := Affixes.make_weapon(base, affixes)
	var p := raid_player()
	if p != null and p.has_method("equip_into_current_slot"):
		var old: Variant = p.call("equip_into_current_slot", w)
		if old is WeaponData:
			_bag_add(LootDB.weapon_item(old as WeaponData), 1)
		return "%s en main" % w.display_name
	if Profile.add_weapon(id, affixes) <= 0:
		return ""
	Profile.save()
	return "%s ajoutée à la réserve" % w.display_name


## Donne `n` objets `id` : sac de raid en raid, réserve du profil sinon. Message court, vide si refusé.
static func give_item(id: StringName, n: int = 1) -> String:
	if not DevMode.is_available():
		return ""
	var it := LootDB.get_item(id)
	if it == null or n <= 0:
		return ""
	if raid_player() != null:
		var got := _bag_add(it, n)
		return ("%s ×%d dans le sac" % [it.display_name, got]) if got > 0 else "Sac plein"
	Profile.add_item(id, n)
	return "%s ×%d ajouté à la réserve" % [it.display_name, n]


static func _bag_add(it: ItemData, n: int) -> int:
	var ml := Engine.get_main_loop() as SceneTree
	var gs: Node = ml.root.get_node_or_null(^"GameState") if ml != null else null
	var inv: Variant = gs.get("raid_inventory") if gs != null else null
	return (inv as Inventory).add_item(it, n) if inv is Inventory and it != null else 0
