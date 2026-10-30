extends GutTest
## Mode développeur (DevMode) : gemmes et or illimités, uniquement en build de développement.
## Le profil, SaveManager.data et user://save.json sont mis de côté puis restaurés à l'identique.

var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	Profile.from_dict({})
	DevMode.reset()


func after_each() -> void:
	DevMode.reset()
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func _cheapest_paid_skin() -> SkinData:
	var best: SkinData = null
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_CHARACTER):
		if s.price_gems > 0 and not s.is_pass() and (best == null or s.price_gems < best.price_gems):
			best = s
	return best


func test_desactive_par_defaut_dans_balance() -> void:
	assert_false(bool(Balance.get_value("dev", "unlimited_currency", true)), "[dev] unlimited_currency=false")
	assert_false(DevMode.is_unlimited())


func test_debit_nul_quand_actif() -> void:
	Profile.gems = 3
	Profile.gold = 2
	assert_true(DevMode.set_unlimited(true))
	assert_eq(Profile.balance_of(&"gems"), DevMode.UNLIMITED)
	assert_true(Profile.can_afford(&"gold", 1_000_000))
	assert_true(Profile.debit(&"gems", 500))
	assert_true(Profile.debit(&"gold", 10_000))
	assert_eq(Profile.gems, 3, "gemmes réelles intactes")
	assert_eq(Profile.gold, 2, "or réel intact")
	var skin := _cheapest_paid_skin()
	assert_not_null(skin)
	assert_true(Profile.buy_skin(skin.id), "skin acheté sans assez de gemmes réelles")
	assert_eq(Profile.gems, 3)


func test_achats_or_gratuits_quand_actif() -> void:
	Profile.gold = 0
	DevMode.set_unlimited(true)
	assert_true(Profile.buy_weapon(&"smg_mp5"), "arme achetée sans or")
	assert_eq(Profile.gold, 0)
	Profile.items = {"mat_cloth": 4, "mat_chemicals": 1}
	assert_gt(RecipeBook.get_recipe(&"craft_bandage").gold_cost, 0)
	assert_true(Profile.craft(&"craft_bandage"), "artisanat sans or")
	assert_eq(Profile.gold, 0)
	assert_eq(Profile.item_count(&"bandage"), 2, "ingrédients consommés normalement, résultat obtenu")


func test_debit_normal_quand_inactif() -> void:
	Profile.gems = 10
	Profile.gold = 100
	assert_false(DevMode.is_unlimited())
	assert_eq(Profile.balance_of(&"gems"), 10)
	assert_false(Profile.debit(&"gems", 11), "solde insuffisant")
	assert_eq(Profile.gems, 10)
	assert_true(Profile.debit(&"gems", 4))
	assert_eq(Profile.gems, 6)
	assert_true(Profile.debit(&"gold", 100))
	assert_eq(Profile.gold, 0)
	assert_false(Profile.debit(&"gold", 1))
	assert_false(Profile.debit(&"inconnue", 1), "monnaie inconnue")
	assert_true(Profile.debit(&"gems", 0), "débit nul toujours accepté")


func test_impossible_hors_build_debug() -> void:
	DevMode.build_check = func() -> bool: return false
	assert_false(DevMode.is_available())
	assert_false(DevMode.set_unlimited(true), "refusé en version publiée")
	assert_false(DevMode.is_unlimited())
	assert_false(DevMode.toggle())
	Profile.gems = 5
	assert_false(Profile.debit(&"gems", 50))
	assert_true(Profile.debit(&"gems", 5))
	assert_eq(Profile.gems, 0, "débit réel")


func test_actif_avant_publication_puis_build_release() -> void:
	DevMode.set_unlimited(true)
	assert_true(DevMode.is_unlimited())
	DevMode.build_check = func() -> bool: return false
	assert_false(DevMode.is_unlimited(), "jamais actif hors build de développement")
	assert_eq(Profile.balance_of(&"gold"), Profile.gold)


func test_solde_sauvegarde_inchange_apres_bascule() -> void:
	Profile.gems = 42
	Profile.gold = 1234
	Profile.save()
	var before: Dictionary = (SaveManager.data["profile"] as Dictionary).duplicate(true)
	DevMode.set_unlimited(true)
	Profile.debit(&"gems", 40)
	Profile.debit(&"gold", 1000)
	Profile.save()
	DevMode.set_unlimited(false)
	Profile.save()
	var after: Dictionary = SaveManager.data["profile"]
	assert_eq(int(after["gems"]), 42)
	assert_eq(int(after["gold"]), 1234)
	assert_eq(int(after["gems"]), int(before["gems"]))
	assert_eq(int(after["gold"]), int(before["gold"]))
	assert_eq(Profile.gems, 42, "vrai solde retrouvé")
	assert_eq(Profile.balance_of(&"gold"), 1234)


func test_bascule_notifie_et_compteurs_infini() -> void:
	watch_signals(Profile)
	var counter := GemCounter.new()
	add_child_autofree(counter)
	DevMode.set_unlimited(true)
	assert_signal_emitted(Profile, "gems_changed")
	assert_eq(counter.value_label.text, DevMode.SYMBOL)
	DevMode.set_unlimited(false)
	assert_eq(counter.value_label.text, str(Profile.gems))


func test_panneau_dev_bascule() -> void:
	var p := get_node_or_null(^"/root/GameState/DevPanel") as DevPanel
	assert_not_null(p, "DevPanel créé par GameState en build debug")
	if p == null:
		return
	assert_false(p.badge.visible)
	p.toggle.button_pressed = true
	assert_true(DevMode.is_unlimited(), "bascule du panneau F3")
	assert_true(p.badge.visible, "badge DEV affiché")
	p.toggle.button_pressed = false
	assert_false(DevMode.is_unlimited())
	assert_false(p.badge.visible)
	DevMode.build_check = func() -> bool: return false
	assert_null(DevPanel.attach(self), "aucun panneau hors build de développement")
