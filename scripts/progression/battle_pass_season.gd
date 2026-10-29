class_name BattlePassSeason
extends Resource
## Saison du pass de combat (data/battle_pass/season_XX.tres) : paliers, XP par palier
## (croissante : xp_base + xp_step × (palier - 1)), récompenses des pistes gratuite et premium.
## Récompense = Dictionary {type, amount, id} :
##   type "gems" (amount), "gold" (amount : pièces d'or), "item" (id d'ItemData, amount),
##   "skin" (id de SkinData). {} = pas de récompense à ce palier.
## Index du tableau = palier - 1.

@export var id: StringName = &""
@export var display_name: String = ""
## Sous-titre affiché sous le nom (thème de la saison).
@export var subtitle: String = ""
@export var tiers: int = 30
@export var xp_base: int = 250
@export var xp_step: int = 25
## Fin de saison (AAAA-MM-JJ, UTC), affichage seulement.
@export var ends_on: String = ""
@export var free_rewards: Array[Dictionary] = []
@export var premium_rewards: Array[Dictionary] = []


## XP nécessaire pour passer du palier `tier - 1` au palier `tier` (1..tiers).
func xp_for_tier(tier: int) -> int:
	return xp_base + xp_step * maxi(tier - 1, 0)


## XP cumulée pour atteindre le palier `tier` (0 → 0).
func xp_total_for(tier: int) -> int:
	var t := 0
	for i: int in range(1, clampi(tier, 0, tiers) + 1):
		t += xp_for_tier(i)
	return t


## Récompense d'une piste ("free" / "premium") à un palier (1..tiers) ; {} si aucune.
func reward(tier: int, track: StringName) -> Dictionary:
	var list: Array[Dictionary] = premium_rewards if track == &"premium" else free_rewards
	var i := tier - 1
	return list[i] if i >= 0 and i < list.size() else {}


## Ids des skins offerts par la saison (piste premium et gratuite).
func skin_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for list: Array[Dictionary] in [free_rewards, premium_rewards]:
		for r: Dictionary in list:
			if str(r.get("type", "")) == "skin":
				out.append(StringName(str(r.get("id", ""))))
	return out
