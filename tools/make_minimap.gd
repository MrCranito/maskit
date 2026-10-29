extends SceneTree
## Produit l'image de mini-carte d'un paquet pré-rendu (assets/prerender/<biome>/<seed>/minimap.webp)
## en assemblant les tuiles t_*.webp réduites (facteur [minimap] pack_downscale, défaut 8).
## Usage : godot --headless --path . --script tools/make_minimap.gd -- res://assets/prerender/far_west/642439/ [facteur]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://assets/prerender/far_west/642439/"
	if not dir.ends_with("/"):
		dir += "/"
	var factor := int(args[1]) if args.size() > 1 else 8
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "map.json"))
	var ip: Array = meta["image_px"]
	var out := Image.create(int(ceil(float(ip[0]) / factor)), int(ceil(float(ip[1]) / factor)), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.08, 0.1, 0.14, 1))
	for t: Dictionary in meta["tiles"]:
		var p: Array = t["px"]
		var tex := load(dir + String(t["file"])) as Texture2D
		if tex == null:
			push_error("tuile illisible " + String(t["file"]))
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w := maxi(int(round(float(p[2]) / factor)), 1)
		var h := maxi(int(round(float(p[3]) / factor)), 1)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(int(round(float(p[0]) / factor)), int(round(float(p[1]) / factor))))
	var path := ProjectSettings.globalize_path(dir + "minimap.webp")
	out.save_webp(path, true, 0.85)
	print("minimap ", out.get_size(), " -> ", path)
	quit()
