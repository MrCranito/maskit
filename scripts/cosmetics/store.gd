class_name Store
extends RefCounted
## Packs de gemmes (balance.cfg [shop] packs = [[gemmes, "prix affiché"], …]).
## Le paiement réel est SIMULÉ : l'achat crédite immédiatement les gemmes et journalise
## « paiement simulé ». Les gemmes ne servent qu'aux skins (aucun avantage en jeu).
##
## TODO paiement réel : remplacer le corps de purchase_pack() par une requête au store natif,
## et ne créditer les gemmes (Profile.add_gems) que dans le rappel de succès, après
## validation du reçu (idéalement côté serveur) :
##   - Android : plugin Godot Google Play Billing (GodotGooglePlayBilling) — querySkuDetails /
##     purchase(sku) puis acknowledgePurchase + consumePurchase (produits consommables).
##   - iOS : plugin StoreKit (godot-ios-plugins « inappstore ») — request_product_info /
##     purchase({product_id}) puis finish_transaction.
## Identifiants produits suggérés : gems_<quantité> (ex. gems_450), à déclarer dans les consoles.


## Vrai tant que les comptes des stores ne sont pas branchés (badge « Paiement simulé »).
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


## Achète le pack `index` (paiement simulé). Renvoie false si l'index est invalide.
static func purchase_pack(index: int) -> bool:
	var list := packs()
	if index < 0 or index >= list.size():
		return false
	var p: Dictionary = list[index]
	# TODO : paiement réel (voir l'en-tête). Ici : succès immédiat.
	print("Store: paiement simulé — %s (%d gemmes, %s)" % [p["product_id"], int(p["gems"]), p["price"]])
	Profile.add_gems(int(p["gems"]))
	return true
