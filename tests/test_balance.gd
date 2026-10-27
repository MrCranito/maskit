extends GutTest
## Vérifie que l'autoload Balance charge data/balance.cfg et expose ses valeurs.

const BALANCE_PATH := "res://data/balance.cfg"


func test_fichier_balance_existe() -> void:
	assert_true(FileAccess.file_exists(BALANCE_PATH), "data/balance.cfg doit exister")


func test_fichier_balance_se_parse() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(BALANCE_PATH), OK, "balance.cfg doit être un ConfigFile valide")


func test_autoload_balance_present() -> void:
	assert_not_null(get_node_or_null("/root/Balance"), "l'autoload Balance doit être chargé")


func test_player_max_hp_positif() -> void:
	assert_gt(Balance.get_float("player", "max_hp", -1.0), 0.0)


func test_player_move_speed_positif() -> void:
	assert_gt(Balance.get_float("player", "move_speed", -1.0), 0.0)


func test_arme_par_defaut_coherente() -> void:
	assert_gt(Balance.get_float("weapon_default", "damage", -1.0), 0.0)
	assert_gt(Balance.get_float("weapon_default", "fire_rate", -1.0), 0.0)
	assert_gt(Balance.get_float("weapon_default", "range", -1.0), 0.0)


func test_cle_absente_renvoie_defaut() -> void:
	assert_eq(Balance.get_float("section_inexistante", "cle", 42.0), 42.0)
	assert_eq(Balance.get_value("section_inexistante", "cle", "defaut"), "defaut")


func test_get_value_renvoie_type_d_origine() -> void:
	var v: Variant = Balance.get_value("player", "auto_fire_only_when_still", null)
	assert_typeof(v, TYPE_BOOL)


func test_valeurs_identiques_au_fichier() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BALANCE_PATH)
	for section: String in cfg.get_sections():
		for key: String in cfg.get_section_keys(section):
			assert_eq(Balance.get_value(section, key), cfg.get_value(section, key),
				"%s/%s doit correspondre au fichier" % [section, key])
