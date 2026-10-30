extends GutTest
## Monnaie peinte et onglet Gemmes de la boutique : images de art/blender/build_currency.py
## chargées (gemme, pièce, illustrations des packs), repli sur le dessin en code sans image,
## rubans « Meilleure offre » / « Populaire » calculés, pack populaire choisi d'office, et tout
## l'onglet tient à l'écran en 1280 x 720 comme en 2000 x 923 (téléphone large).

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	Profile.from_dict({"gems": 0})


func after_each() -> void:
	CurrencyArt.enabled = true
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_data
	SaveManager.save()
	ShopScreen.last_tab = &"character"


func _shop() -> ShopScreen:
	var s := (load("res://scenes/ui/menus/shop.tscn") as PackedScene).instantiate() as ShopScreen
	add_child_autofree(s)
	return s


# --- Images --------------------------------------------------------------------------------

func test_images_peintes_chargees() -> void:
	for t: Texture2D in [CurrencyArt.gem(), CurrencyArt.coin()]:
		assert_not_null(t, "Gemme et pièce peintes présentes (assets/ui/currency)")
		if t != null:
			assert_gte(t.get_width(), 256)
	for i: int in CurrencyArt.PACK_IMAGES:
		var p := CurrencyArt.pack(i)
		assert_not_null(p, "Illustration du pack %d" % (i + 1))
		if p != null:
			assert_gte(p.get_width(), 256)
	assert_eq(CurrencyArt.pack(-3), CurrencyArt.pack(0), "Indice négatif : le plus petit pack")
	assert_eq(CurrencyArt.pack(42), CurrencyArt.pack(CurrencyArt.PACK_IMAGES - 1), "Au-delà : la dernière illustration")


func test_repli_sans_image() -> void:
	CurrencyArt.enabled = false
	assert_null(CurrencyArt.gem())
	assert_null(CurrencyArt.coin())
	assert_null(CurrencyArt.pack(0))
	var art := ShopOffers.pack_art(0)
	assert_true(art is GemIcon, "Sans illustration : une gemme dessinée")
	art.free()
	# Les icônes se dessinent sans erreur, avec ou sans image (API et tailles inchangées).
	for painted: bool in [true, false]:
		CurrencyArt.enabled = painted
		var row := HBoxContainer.new()
		add_child_autofree(row)
		var g := GemIcon.new()
		g.custom_minimum_size = Vector2(34, 34)
		row.add_child(g)
		var c := GoldCounter.CoinIcon.new()
		c.custom_minimum_size = Vector2(32, 32)
		row.add_child(c)
		var m := MenuGlyph.new(&"coin", MenuKit.COIN, 30)
		row.add_child(m)
		await wait_frames(2)
		assert_eq(g.size.x, 34.0, "Taille d'appel conservée")
		assert_eq(m.size.x, 30.0)
	var off := GemIcon.new()
	off.use_art = false
	add_child_autofree(off)
	await wait_frames(1)
	assert_false(off.use_art)


# --- Rubans et choix d'office -------------------------------------------------------------

func test_meilleure_offre_calculee() -> void:
	var packs := Store.packs()
	assert_gte(packs.size(), 2)
	var best := 0
	for i: int in packs.size():
		var r := float(packs[i]["gems"]) / Store.pack_euros(packs[i])
		if r >= float(packs[best]["gems"]) / Store.pack_euros(packs[best]):
			best = i
	assert_eq(Store.best_value_pack(), best, "Meilleur rapport gemmes / euro")
	assert_eq(ShopOffers.pack_ribbon(best), "Meilleure offre")
	var pop := Store.popular_pack()
	assert_eq(pop, clampi(int(Balance.get_value("shop", "popular_pack", 2)), 0, packs.size() - 1), "Populaire : balance.cfg")
	if pop != best:
		assert_eq(ShopOffers.pack_ribbon(pop), "Populaire")
	var n := 0
	for i: int in packs.size():
		if not ShopOffers.pack_ribbon(i).is_empty():
			n += 1
	assert_eq(n, 1 if pop == best else 2, "Seuls ces deux packs ont un ruban")


func test_onglet_gemmes_rubans_et_choix() -> void:
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"gems")
	await wait_frames(2)
	assert_eq(s.offers.selected, Store.popular_pack(), "Le pack populaire est choisi d'office")
	assert_eq(s.offers.cards.size(), Store.packs().size())
	for i: int in s.offers.cards.size():
		var card: Button = s.offers.cards[i]
		var rib := card.find_child("Ribbon", false, false)
		var want := ShopOffers.pack_ribbon(i)
		if want.is_empty():
			assert_null(rib, "Pas de ruban sur le pack %d" % i)
		else:
			assert_not_null(rib, "Ruban sur le pack %d" % i)
			if rib != null:
				assert_eq((rib.get_child(0) as Label).text, want)
		assert_not_null(card.find_child("Art", false, false), "Illustration du pack %d" % i)
		assert_not_null(card.find_child("PriceButton", false, false), "Prix sur un vrai bouton")
		assert_eq(card.find_child("Bonus", false, false) != null, ShopOffers.pack_bonus_pct(i) > 0, "Bonus %%")
	# Premier achat doublé : visible sur les cartes et dans le bandeau.
	assert_true(Store.first_bonus_available())
	assert_not_null(s.offers.find_child("WelcomeBanner", true, false))
	assert_not_null(s.offers.find_child("FirstBonus", true, false))
	assert_not_null(s.offers.find_child("SlabArt", true, false), "Grande illustration dans le bandeau")


func test_bouton_prix_choisit_puis_achete() -> void:
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"gems")
	await wait_frames(1)
	var pb := s.offers.cards[0].find_child("PriceButton", false, false) as Button
	pb.pressed.emit()
	assert_eq(s.offers.selected, 0, "Toucher le prix d'une autre carte la choisit")
	assert_eq(Profile.gems, 0, "… sans acheter")
	pb = s.offers.cards[0].find_child("PriceButton", false, false) as Button
	var expected := Store.pack_gems_now(0)
	pb.pressed.emit()
	assert_eq(Profile.gems, 0, "Toucher le prix de la carte choisie demande d'abord confirmation")
	assert_not_null(s.offers.last_confirm, "Fenêtre de confirmation ouverte")
	s.offers.last_confirm.confirmed.emit()
	assert_eq(Profile.gems, expected, "Confirmé : achat (paiement simulé)")


# --- Tient à l'écran --------------------------------------------------------------------------

func test_onglet_gemmes_tient_a_l_ecran() -> void:
	for vp: Vector2 in [Vector2(1280, 720), Vector2(2000, 923)]:
		for tab: StringName in [&"gems", &"packs"]:
			await _check_fits(vp, tab)


func _check_fits(vp: Vector2, tab: StringName) -> void:
	var s := _shop()
	await wait_frames(2)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = vp
	s.show_tab(tab)
	await wait_frames(3)
	var screen := Rect2(Vector2.ZERO, vp)
	var slab := (s.offers.get_node("Slab") as Control).get_global_rect()
	assert_true(screen.grow(1.0).encloses(slab), "%s %s : bandeau dans l'écran" % [vp, tab])
	var act := s.offers.action_button.get_global_rect()
	assert_true(screen.encloses(act), "%s %s : bouton Acheter dans l'écran" % [vp, tab])
	assert_true(slab.grow(1.0).encloses(act), "%s %s : bouton Acheter dans le bandeau" % [vp, tab])
	for card: Button in s.offers.cards:
		var cr := card.get_global_rect()
		assert_true(screen.grow(1.0).encloses(cr), "%s %s : %s dans l'écran" % [vp, tab, card.name])
		assert_false(cr.intersects(slab.grow(-90.0)), "%s %s : %s pas sous le bandeau" % [vp, tab, card.name])
		var pr := (card.find_child("PriceButton", false, false) as Control).get_global_rect()
		assert_true(cr.grow(1.0).encloses(pr), "%s %s : prix dans la carte" % [vp, tab])
		if tab == &"gems":
			var info := (card.find_child("Info", false, false) as Control).get_global_rect()
			assert_lte(info.end.y, pr.position.y + 1.0, "%s : nombre de gemmes au-dessus du prix" % vp)
			var amount := card.find_child("Amount", true, false) as Label
			assert_lte(amount.get_minimum_size().x, cr.size.x, "%s : nombre de gemmes dans la carte" % vp)
			var rib := card.find_child("Ribbon", false, false) as Control
			if rib != null:
				var l := rib.get_child(0) as Label
				var w := l.get_theme_font("font").get_string_size(l.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
					l.get_theme_font_size("font_size")).x
				assert_lte(w, l.size.x + 1.0, "%s : ruban lisible en entier" % vp)
	if tab == &"gems":
		var amt := s.offers.find_child("SlabArt", true, false) as Control
		assert_true(slab.grow(1.0).encloses(amt.get_global_rect()), "%s : illustration dans le bandeau" % vp)
		assert_gte(amt.size.y, 100.0, "%s : grande illustration" % vp)
