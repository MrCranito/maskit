extends GutTest
## Taille de l'APK (PR « chore/taille-apk ») : réglages d'import des textures lourdes et filtres
## d'export. Les règles sont appliquées par tools/apply_texture_imports.py (à relancer après
## l'ajout d'assets) ; ce test échoue si un nouvel asset y échappe.

const PRESETS := "res://export_presets.cfg"
## Dossiers jamais utilisés à l'exécution (le jeu ne les charge pas) : hors de tout export.
const NOT_EXPORTED := ["docs/*", "tools/*", "art/*", "server/*", "supabase/*", "tests/*", "addons/gut/*"]


func _params(import_path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK or String(cfg.get_value("remap", "importer", "")) != "texture":
		return {}
	var res := {}
	for k: String in cfg.get_section_keys("params"):
		res[k] = cfg.get_value("params", k)
	return res


func _imports(dir: String, out: Array[String]) -> Array[String]:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".import"):
			out.append(dir.path_join(f))
	for sub: String in d.get_directories():
		_imports(dir.path_join(sub), out)
	return out


func test_presets_exclude_unused_folders() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var n := 0
	for s: String in cfg.get_sections():
		if not cfg.has_section_key(s, "exclude_filter"):
			continue
		n += 1
		var filters: PackedStringArray = String(cfg.get_value(s, "exclude_filter")).split(",", false)
		for i in filters.size():
			filters[i] = filters[i].strip_edges()
		for f: String in NOT_EXPORTED:
			assert_true(f in filters, "%s (%s) : exclude_filter doit contenir %s" % [s, cfg.get_value(s, "name"), f])
	assert_gt(n, 0, "aucun préréglage d'export")


func test_android_arm64_only() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	for s: String in cfg.get_sections():
		if String(cfg.get_value(s, "platform", "")) != "Android":
			continue
		var o := s + ".options"
		assert_true(bool(cfg.get_value(o, "architectures/arm64-v8a")), "arm64-v8a exporté")
		for a: String in ["armeabi-v7a", "x86", "x86_64"]:
			assert_false(bool(cfg.get_value(o, "architectures/" + a)), "architecture %s inutile dans l'APK" % a)


func test_no_runtime_reference_to_excluded_folders() -> void:
	# Une ressource exportée qui dépendrait d'un dossier exclu serait cassée dans l'APK.
	for root: String in ["res://scenes", "res://data", "res://assets"]:
		for f: String in _files(root, [".tscn", ".tres"], []):
			for dep: String in ResourceLoader.get_dependencies(f):
				var p := dep.get_slice("::", 2) if dep.contains("::") else dep
				for bad: String in ["res://docs/", "res://tools/", "res://art/"]:
					assert_false(p.begins_with(bad), "%s dépend de %s (exclu de l'export)" % [f, p])


func _files(dir: String, exts: Array, out: Array[String]) -> Array[String]:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f: String in d.get_files():
		for e: String in exts:
			if f.ends_with(e):
				out.append(dir.path_join(f))
	for sub: String in d.get_directories():
		_files(dir.path_join(sub), exts, out)
	return out


func test_prerender_tiles_lossy_ids_lossless() -> void:
	var n_lossy := 0
	var n_ids := 0
	for p: String in _imports("res://assets/prerender", []):
		var prm := _params(p)
		if prm.is_empty():
			continue
		var name := p.get_file().trim_suffix(".import")
		assert_false(bool(prm.get("mipmaps/generate", false)), "%s : pas de mipmaps" % name)
		if name.begins_with("o_") or name == "footprint.png":
			n_ids += 1
			assert_eq(int(prm.get("compress/mode", -1)), 0, "%s : ids / masque sans perte" % p)
		else:
			n_lossy += 1
			assert_eq(int(prm.get("compress/mode", -1)), 1, "%s : WebP avec perte (tools/apply_texture_imports.py)" % p)
			assert_gte(float(prm.get("compress/lossy_quality", 0.0)), 0.85, "%s : qualité ≥ 0,85" % p)
	assert_gt(n_lossy, 0)
	assert_gt(n_ids, 0)


func test_no_raw_vram_textures() -> void:
	# VRAM non compressé à l'export (mode 2) : ASTC brut 8 bits/px + double BPTC → Basis Universal.
	for base: String in ["res://assets/sprites", "res://assets/textures"]:
		for p: String in _imports(base, []):
			var prm := _params(p)
			if not prm.is_empty():
				assert_ne(int(prm.get("compress/mode", -1)), 2, "%s : Basis Universal (mode 4) plutôt que VRAM brut" % p)


func test_enemy_atlases_basis_without_mipmaps() -> void:
	var n := 0
	for p: String in _imports("res://assets/sprites/enemies", []):
		if not p.ends_with("_atlas.png.import"):
			continue
		n += 1
		var prm := _params(p)
		assert_eq(int(prm.get("compress/mode", -1)), 4, "%s : Basis Universal" % p)
		assert_false(bool(prm.get("mipmaps/generate", true)), "%s : pas de mipmaps (zoom quasi fixe)" % p)
	assert_gt(n, 10, "atlas d'ennemis trouvés")
