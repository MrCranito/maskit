class_name BiomeAssets
extends RefCounted
## Recherche des ressources propres au biome du raid en cours, avec repli Far West.
## Le raid appelle BiomeAssets.set_world(world) avant de construire l'étage.

const FALLBACK_CONTAINERS_DIR := "res://assets/sprites/far_west/containers/"
const SPRITE_EXTS: Array[String] = [".png", ".svg"]

## Dossier des conteneurs et cachettes du biome courant.
static var containers_dir: String = FALLBACK_CONTAINERS_DIR


static func set_world(world: Resource) -> void:
	var d: Variant = world.get("containers_dir") if world != null else null
	containers_dir = String(d) if d != null and String(d) != "" else FALLBACK_CONTAINERS_DIR


## Chemin du sprite `base_name` (sans extension) : biome courant puis `fallback_dir`.
## Renvoie le chemin .svg du repli s'il n'existe nulle part (le chargeur gère l'absence).
static func find_sprite(base_name: String, fallback_dir: String = FALLBACK_CONTAINERS_DIR) -> String:
	for dir: String in [containers_dir, fallback_dir]:
		for ext: String in SPRITE_EXTS:
			var p := dir + base_name + ext
			if ResourceLoader.exists(p):
				return p
	return fallback_dir + base_name + ".svg"
