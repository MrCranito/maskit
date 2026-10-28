extends RefCounted
## Définitions des conteneurs fouillables de la station sous-marine, au format de
## LootContainer.DEFS (scale : unités monde par px du PNG ; block : collision au sol ;
## reach : portée d'interaction en plus ; shadow : demi-largeur de l'ombre code (0 : l'ombre
## est peinte dans le sprite) ; foot : px entre les pieds et le bas du PNG).
## Sprites : assets/sprites/underwater/containers/<kind>.png et <kind>_open.png
## (art/blender/underwater/uw_containers.py, mêmes valeurs de foot).
## Tables : data/loot_tables/<kind>.tres.
##
## LootContainer.create() remplace aujourd'hui tout kind absent de LootContainer.DEFS par
## « crate » : ces définitions doivent y être fusionnées (changement demandé dans le rapport
## du biome, cf. BiomeRegistry pour les ennemis).

const DEFS := {
	&"uw_crate": {"name": "Caisse étanche", "scale": 0.55, "block": Vector2(56, 18), "reach": 4.0, "shadow": 0.0, "foot": 24.0},
	&"uw_locker": {"name": "Casier", "scale": 0.55, "block": Vector2(36, 14), "reach": 4.0, "shadow": 0.0, "foot": 22.0},
	&"uw_lab_cabinet": {"name": "Armoire de laboratoire", "scale": 0.55, "block": Vector2(50, 14), "reach": 4.0, "shadow": 0.0, "foot": 22.0},
	&"uw_sample_chest": {"name": "Coffre à échantillons", "scale": 0.55, "block": Vector2(56, 20), "reach": 4.0, "shadow": 0.0, "foot": 26.0},
	&"uw_diver_corpse": {"name": "Plongeur noyé", "scale": 0.55, "block": Vector2.ZERO, "reach": 14.0, "shadow": 0.0, "foot": 30.0},
	&"uw_tank": {"name": "Réservoir", "scale": 0.55, "block": Vector2(40, 18), "reach": 4.0, "shadow": 0.0, "foot": 26.0},
}
