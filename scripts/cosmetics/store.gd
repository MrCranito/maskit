class_name Store
extends RefCounted
## Packs de gemmes (balance.cfg [shop] packs = [[gemmes, "prix affiché"], …]), packs à contenu
## ([shop] bundles) et coffres de skins GRATUITS ([chests]).
##  - Premier achat : les gemmes du premier pack acheté sont multipliées par
##    [shop] first_purchase_multiplier (une seule fois par profil).
##  - Packs à contenu : skins + gemmes ; un skin déjà possédé est remboursé à son prix en gemmes ;
##    un pack « once » ne s'achète qu'une fois.
##  - Coffres : jamais vendus (pas de loot box payante). 1 coffre offert toutes les
##    [chests] every_extractions extractions réussies ; taux par rareté affichés ; garantie Épique
##    ou mieux après [chests] pity coffres sans Épique ; tirage parmi les skins de boutique pas
##    encore possédés de la rareté tirée, sinon doublon remboursé ([chests] duplicate_refund).
## Paiement : quand le cloud est joignable (CloudSync.purchases_online), l'achat est envoyé au
## serveur (Edge Function verify_purchase) qui vérifie le reçu auprès du store et crédite ;
## le jeu ne crédite les gemmes / skins (fulfill_pack, fulfill_bundle) qu'au retour du serveur
## (signal CloudSync.purchase_finished). Tant que les plugins de paiement natifs ne sont pas
## branchés, le reçu envoyé est « simulated » : le serveur ne l'accepte que si son secret
## ALLOW_SIMULATED_PURCHASES vaut "true" (jamais en production). Sans cloud (tests, éditeur hors
## ligne), repli : crédit local immédiat journalisé « paiement simulé ».
## Les gemmes ne servent qu'aux skins (aucun avantage en jeu) et n'expirent jamais.
##
## TODO plugins natifs (à brancher dans native_receipt()) :
##   - Android : plugin Google Play Billing — purchase(product_id) → purchaseToken, puis
##     consumePurchase après le retour du serveur ; prix affiché = ProductDetails du store.
##   - iOS : StoreKit 2 — purchase(product_id) → transaction.id, puis finish() après le retour ;
##     prix affiché = Product.displayPrice.
## Identifiants produits (catalogue serveur `products`) : gems_<quantité>, bundle_<id>.


## Vrai tant que les plugins de paiement natifs ne sont pas branchés (badge « Paiement simulé »).
const SIMULATED := true


## Packs : [{gems: int, price: String, product_id: String}].
static func packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = Balance.get_value("shop", "packs", [])
	if raw is Array:
		for p: Variant in raw:
			if p is Array and (p as Array).size() >= 2:
				var g := int(p[0])
				out.append({"gems": g, "price": str(p[1]), "product_id": "gems_%d" % g})
	return out


## Premier achat encore disponible (gemmes doublées sur le pack choisi) ?
static func first_bonus_available() -> bool:
	return not Profile.shop_first_bonus_used and first_bonus_multiplier() > 1


static func first_bonus_multiplier() -> int:
	return maxi(int(Balance.get_value("shop", "first_purchase_multiplier", 2)), 1)


## Gemmes que créditerait le pack `index` maintenant (bonus de premier achat compris).
static func pack_gems_now(index: int) -> int:
	var list := packs()
	if index < 0 or index >= list.size():
		return 0
	var g := int(list[index]["gems"])
	return g * first_bonus_multiplier() if first_bonus_available() else g


## Achète le pack `index`. Renvoie false si l'index est invalide. Avec le cloud : l'achat part au
## serveur (résultat asynchrone, CloudSync.purchase_finished → fulfill_pack) ; sans : crédit local.
static func purchase_pack(index: int) -> bool:
	var list := packs()
	if index < 0 or index >= list.size():
		return false
	var p: Dictionary = list[index]
	var cs: Node = _cloud()
	if cs != null and bool(cs.call("purchases_online")):
		if bool(cs.get("purchase_busy")):
			return false
		_pending[str(p["product_id"])] = {"kind": "pack", "index": index}
		_connect_cloud(cs)
		cs.call("purchase", "simulated", str(p["product_id"]), native_receipt(str(p["product_id"])))
		return true
	var credited := pack_gems_now(index)
	print("Store: paiement simulé (local) — %s (%d gemmes, %s)" % [p["product_id"], credited, p["price"]])
	fulfill_pack(index, credited)
	return true


## Crédit d'un pack : appelé après vérification serveur (ou en repli local).
static func fulfill_pack(_index: int, gems: int) -> void:
	Profile.shop_first_bonus_used = true
	Profile.add_gems(gems)


## Reçu natif pour le serveur : {"transaction_id": …} (StoreKit 2) ou {"purchase_token": …}
## (Play Billing). Vide tant que les plugins ne sont pas branchés (reçu « simulated »).
static func native_receipt(_product_id: String) -> Dictionary:
	return {}


static var _pending: Dictionary = {}
static var _connected: bool = false


static func _cloud() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(^"CloudSync") if ml != null else null


static func _connect_cloud(cs: Node) -> void:
	if _connected or cs == null:
		return
	_connected = true
	cs.connect(&"purchase_finished", _on_purchase_finished)


static func _on_purchase_finished(ok: bool, product_id: String, gems: int, _entitlements: Array, message: String) -> void:
	var req: Variant = _pending.get(product_id)
	_pending.erase(product_id)
	if not ok:
		push_warning("Store: achat %s refusé : %s" % [product_id, message])
		return
	if not (req is Dictionary):
		return
	match str((req as Dictionary).get("kind", "")):
		"pack":
			fulfill_pack(int((req as Dictionary)["index"]), gems)
		"bundle":
			fulfill_bundle(StringName(str((req as Dictionary)["id"])), gems)


## Applique les droits durables connus du serveur (restauration sur un nouvel appareil, bouton
## « Restaurer mes achats ») : un pack à contenu acheté mais absent du profil est ré-accordé
## (skins seulement : les gemmes étaient dans la sauvegarde).
static func apply_entitlements(list: Array) -> void:
	for e: Variant in list:
		var key := str(e)
		if key.begins_with("bundle_"):
			var id := StringName(key.trim_prefix("bundle_"))
			if not bundle(id).is_empty() and not Profile.bundles_bought.has(id):
				fulfill_bundle(id, 0)


# --- Packs à contenu -------------------------------------------------------------------

## Packs à contenu ([shop] bundles) : [{id, name, price, gems, skins: Array[StringName],
## once: bool, ref_gems: int, product_id}]. Les skins inconnus sont ignorés.
static func bundles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = Balance.get_value("shop", "bundles", [])
	if not raw is Array:
		return out
	for b: Variant in raw:
		if not b is Dictionary:
			continue
		var d := b as Dictionary
		var sk: Array[StringName] = []
		for id: Variant in d.get("skins", []):
			if SkinData.get_skin(StringName(str(id))) != null:
				sk.append(StringName(str(id)))
		var bid := str(d.get("id", ""))
		if bid.is_empty():
			continue
		out.append({"id": StringName(bid), "name": str(d.get("name", bid)), "price": str(d.get("price", "")),
			"gems": int(d.get("gems", 0)), "skins": sk, "once": bool(d.get("once", false)),
			"ref_gems": int(d.get("ref_gems", 0)), "product_id": "bundle_" + bid})
	return out


static func bundle(id: StringName) -> Dictionary:
	for b: Dictionary in bundles():
		if b["id"] == id:
			return b
	return {}


## Valeur affichée d'un pack : prix boutique des skins + gemmes.
static func bundle_value(b: Dictionary) -> int:
	var v := int(b.get("gems", 0))
	for id: StringName in b.get("skins", []):
		v += SkinData.get_skin(id).price_gems
	return v


static func bundle_available(id: StringName) -> bool:
	var b := bundle(id)
	return not b.is_empty() and not (bool(b["once"]) and Profile.bundles_bought.has(id))


## Achète un pack à contenu. Renvoie {} si indisponible ; avec le cloud : {"pending": true} (le
## contenu arrive au retour du serveur, CloudSync.purchase_finished → fulfill_bundle) ; sans :
## {skins: Array[StringName] (nouveaux), refunded: int (gemmes des doublons), gems: int}.
static func purchase_bundle(id: StringName) -> Dictionary:
	if not bundle_available(id):
		return {}
	var b := bundle(id)
	var cs: Node = _cloud()
	if cs != null and bool(cs.call("purchases_online")):
		if bool(cs.get("purchase_busy")):
			return {}
		_pending[str(b["product_id"])] = {"kind": "bundle", "id": String(id)}
		_connect_cloud(cs)
		cs.call("purchase", "simulated", str(b["product_id"]), native_receipt(str(b["product_id"])))
		return {"pending": true}
	print("Store: paiement simulé (local) — %s (%s)" % [b["product_id"], b["price"]])
	return fulfill_bundle(id, int(b["gems"]))


## Crédit d'un pack à contenu (skins + gemmes `gems` + remboursement des doublons) : après
## vérification serveur, ou en repli local. Renvoie {skins, refunded, gems}.
static func fulfill_bundle(id: StringName, gems: int) -> Dictionary:
	var b := bundle(id)
	if b.is_empty():
		return {}
	var got: Array[StringName] = []
	var refunded := 0
	for sid: StringName in b["skins"]:
		if Profile.owns_skin(sid):
			refunded += SkinData.get_skin(sid).price_gems
		else:
			Profile.grant_skin(sid)
			got.append(sid)
	if not Profile.bundles_bought.has(id):
		Profile.bundles_bought.append(id)
	Profile.add_gems(gems + refunded)
	return {"skins": got, "refunded": refunded, "gems": gems}


# --- Coffres de skins (gratuits) ---------------------------------------------------------

## Taux par rareté [[rareté, probabilité]] du plus commun au plus rare ([chests] odds).
static func chest_odds() -> Array:
	var raw: Variant = Balance.get_value("chests", "odds", [[2, 0.7], [3, 0.25], [4, 0.05]])
	var out: Array = []
	if raw is Array:
		for e: Variant in raw:
			if e is Array and (e as Array).size() >= 2:
				out.append([int(e[0]), float(e[1])])
	return out


static func chest_pity() -> int:
	return maxi(int(Balance.get_value("chests", "pity", 10)), 1)


static func chest_every() -> int:
	return maxi(int(Balance.get_value("chests", "every_extractions", 5)), 1)


## Skins pouvant sortir d'un coffre : skins de boutique (pas ceux du pass), de cette rareté.
static func chest_pool(rarity: int) -> Array[SkinData]:
	var out: Array[SkinData] = []
	var kinds: Array[StringName] = [SkinData.KIND_CHARACTER]
	if WeaponSkin.is_enabled():
		kinds.append(SkinData.KIND_WEAPON)
	for k: StringName in kinds:
		for s: SkinData in SkinData.shop_skins(k):
			if s.rarity == rarity and s.price_gems > 0:
				out.append(s)
	return out


## Rareté tirée (garantie appliquée quand le compteur atteint [chests] pity - 1).
static func roll_chest_rarity(rng: RandomNumberGenerator) -> int:
	var odds := chest_odds()
	if odds.is_empty():
		return 2
	var guaranteed := Profile.chest_pity_count >= chest_pity() - 1
	var floor_r := int(Balance.get_value("chests", "pity_min_rarity", 3))
	var total := 0.0
	for e: Array in odds:
		if not guaranteed or int(e[0]) >= floor_r:
			total += float(e[1])
	var x := rng.randf() * total
	for e: Array in odds:
		if guaranteed and int(e[0]) < floor_r:
			continue
		x -= float(e[1])
		if x <= 0.0:
			return int(e[0])
	return int(odds[odds.size() - 1][0])


## Ouvre un coffre gratuit. Renvoie {} s'il n'y en a pas, sinon {skin: SkinData, rarity: int,
## duplicate: bool, refunded: int}.
static func open_chest(rng: RandomNumberGenerator = null) -> Dictionary:
	if Profile.free_chests <= 0:
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var r := roll_chest_rarity(rng)
	var pool := chest_pool(r)
	if pool.is_empty():
		return {}
	var fresh: Array[SkinData] = []
	for s: SkinData in pool:
		if not Profile.owns_skin(s.id):
			fresh.append(s)
	var dup := fresh.is_empty()
	var pick: SkinData = (pool if dup else fresh)[rng.randi() % (pool if dup else fresh).size()]
	var refunded := 0
	Profile.free_chests -= 1
	Profile.chest_pity_count = 0 if r >= int(Balance.get_value("chests", "pity_min_rarity", 3)) else Profile.chest_pity_count + 1
	if dup:
		refunded = int(round(pick.price_gems * float(Balance.get_value("chests", "duplicate_refund", 0.5))))
		Profile.add_gems(refunded)
	else:
		Profile.grant_skin(pick.id)
	return {"skin": pick, "rarity": r, "duplicate": dup, "refunded": refunded}
