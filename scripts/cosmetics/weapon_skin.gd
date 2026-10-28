class_name WeaponSkin
extends RefCounted
## Application d'un skin d'arme (SkinData kind "weapon") sur le sprite d'une arme tenue ou
## d'une icône. Purement visuel. STUB du contrat : implémentation complète par l'agent Menus
## (shader assets/shaders/weapon_skin.gdshader).


## Applique `skin` à `item` (Sprite2D / TextureRect…). skin null = apparence d'origine.
static func apply(item: CanvasItem, skin: SkinData) -> void:
	if item == null:
		return
	if skin == null:
		item.material = null
		return
	item.material = null
