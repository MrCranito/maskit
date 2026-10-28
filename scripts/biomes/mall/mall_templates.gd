extends RefCounted
## Gabarits d'aménagement du centre commercial par rôle de salle (Room.tags[0]) : syntaxe des
## étapes dans scripts/dungeon/gen/furnisher.gd. Seules les salles INTÉRIEURES (boutiques,
## réserves, bureaux, cinéma…) ont un gabarit ; galeries, atrium, parking et toit gardent
## l'ameublement par règles de mall_populator.gd (fontaine, voitures, climatiseurs…).

## Compléments aux définitions de collision de mall_prop.gd (fp : emprise en cases ; tall :
## meuble haut, masque le mur derrière lui ; nudge : décalage visuel).
const META := {
	&"store_shelf": {"fp": Vector2i(3, 1), "centered": true},
	&"cinema_seats": {"fp": Vector2i(3, 1), "centered": true},
	&"checkout": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"clothes_rack": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"medicine_shelf": {"fp": Vector2i(2, 1), "tall": true, "nudge": Vector2(10, 0)},
	&"tv_wall": {"fp": Vector2i(2, 1), "tall": true, "nudge": Vector2(10, 0)},
	&"desk": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"food_table": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"arcade_cabinet": {"tall": true},
	&"filing_cabinet": {"tall": true},
	&"generator": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"bench": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"planter": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"mannequin": {},
	&"popcorn_machine": {"tall": true},
	# Mobilier de l'aménagement (art/blender/mall/build_mall_furniture.py)
	&"gondola": {"fp": Vector2i(2, 1)},
	&"shoe_rack": {"fp": Vector2i(2, 1), "tall": true},
	&"display_table": {"fp": Vector2i(2, 1)},
	&"food_counter": {"fp": Vector2i(3, 1), "tall": true},
	&"office_desk": {"fp": Vector2i(2, 2)},
	&"stock_rack": {"fp": Vector2i(2, 1), "tall": true},
	&"glass_case": {"fp": Vector2i(2, 1)},
	&"bookshelf": {"fp": Vector2i(2, 1), "tall": true},
	&"mall_sofa": {"fp": Vector2i(2, 1)},
	&"tray_cart": {},
}

const ART_SHOP := ["kit_wall_poster", "kit_wall_sale", "kit_wall_shelf", "kit_wall_poster"]
const ART_OFFICE := ["kit_wall_clock", "kit_wall_board", "kit_wall_poster"]
const ART_BACK := ["kit_wall_board", "kit_wall_clock"]

## Boutique « standard » : comptoir-caisse près de l'entrée, rayons le long des murs, présentoirs
## centraux. `wall` : meuble mural ; `center` : îlot ; `extra` : petits objets.
static func _shop(wall: StringName, center: StringName, extra: Array, art: Array = ART_SHOP, wall_ew: StringName = &"") -> Dictionary:
	return {
		"steps": [
			{"op": "along", "kind": &"checkout", "side": "ew", "where": "end", "n": 1, "tag": "till"},
			{"op": "along", "kind": wall, "side": "n", "where": "spread", "n": [3, 6], "every": 1, "tag": "shelf"},
			{"op": "along", "kind": wall_ew if wall_ew != &"" else wall, "side": "ew", "where": "spread", "n": [2, 4], "every": 1, "tag": "shelf", "min_room": [5, 5]},
			{"op": "along", "kind": wall, "side": "s", "where": "spread", "n": [0, 3], "every": 2, "min_room": [7, 7]},
			{"op": "booth", "w": 2, "h": 2, "fill": &"stock_rack", "min_room": [9, 7]},
			{"op": "rows", "kind": center, "axis": "x", "row_gap": 1, "gap": 1, "margin": [2, 3, 2, 2], "max": 6, "min_room": [7, 6]},
			{"op": "fill", "kinds": extra, "ratio": 0.24, "max": 6},
			{"op": "decal", "mode": "center", "piece": &"decal_rug", "min_room": [6, 5]},
			{"op": "art", "pieces": art, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "till", "rel": "sides", "kinds": [&"mall_register"]}, {"mode": "in", "of": "booth"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	}


static var _cache: Dictionary = {}


static func templates() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	_cache = {
		&"shop_clothes": _shop(&"clothes_rack", &"display_table", [&"mannequin", &"clothes_rack", &"palm_pot"], ART_SHOP, &"shoe_rack"),
		&"shop_electronics": _shop(&"tv_wall", &"glass_case", [&"tray_cart", &"palm_pot"], ["kit_wall_tv", "kit_wall_sale", "kit_wall_tv"], &"gondola"),
		&"shop_pharmacy": _shop(&"medicine_shelf", &"gondola", [&"tray_cart", &"palm_pot"], ["kit_wall_sale", "kit_wall_poster", "kit_wall_shelf"]),
		&"shop_toys": _shop(&"store_shelf", &"display_table", [&"toy_pile", &"toy_pile", &"palm_pot"], ["kit_wall_poster", "kit_wall_shelf", "kit_wall_sale"]),
		&"shop_shoes": _shop(&"shoe_rack", &"mall_sofa", [&"mannequin", &"palm_pot"], ART_SHOP),
		&"shop_perfume": _shop(&"medicine_shelf", &"glass_case", [&"mannequin", &"palm_pot"], ["kit_wall_poster", "kit_wall_shelf"]),
		&"shop_books": _shop(&"bookshelf", &"display_table", [&"mall_sofa", &"palm_pot"], ["kit_wall_board", "kit_wall_poster", "kit_wall_clock"]),
		&"shop_sports": _shop(&"shoe_rack", &"clothes_rack", [&"mannequin", &"toy_pile"], ART_SHOP, &"clothes_rack"),
		&"shop_jewelry": {
			"steps": [
				{"op": "along", "kind": &"glass_case", "side": "n", "where": "spread", "n": [2, 3], "every": 1, "tag": "case"},
				{"op": "along", "kind": &"glass_case", "side": "ew", "where": "spread", "n": [1, 2], "every": 1, "tag": "case"},
				{"op": "island", "kind": &"glass_case", "n": [1, 2], "margin": 2, "spacing": 1},
				{"op": "corner", "kind": [&"palm_pot", &"mannequin"], "n": 2},
				{"op": "decal", "mode": "center", "piece": &"decal_rug"},
				{"op": "art", "pieces": ["kit_wall_poster", "kit_wall_clock"], "density": 0.4},
			],
			"loot": [{"mode": "beside", "of": "case", "rel": "sides", "kinds": [&"mall_display", &"mall_jewel_safe"]}, {"mode": "corner"}],
		},
		&"shop_cafe": {
			"steps": [
				{"op": "along", "kind": &"food_counter", "side": "n", "where": "end", "n": 1, "tag": "counter"},
				{"op": "along", "kind": &"checkout", "side": "n", "where": "end", "n": 1, "tag": "counter", "unless": "counter"},
				{"op": "rows", "kind": &"food_table", "axis": "x", "row_gap": 1, "gap": 1, "margin": [1, 3, 1, 1], "max": 6, "tag": "table"},
				{"op": "along", "kind": &"mall_sofa", "side": "ew", "n": [0, 1]},
				{"op": "corner", "kind": [&"palm_pot", &"trash_bin"], "n": 2},
				{"op": "decal", "mode": "near", "of": "table", "piece": &"decal_tray", "n": 1, "jitter": 12.0},
				{"op": "art", "pieces": ["kit_wall_poster", "kit_wall_clock", "kit_wall_board"], "density": 0.4},
			],
			"loot": [{"mode": "beside", "of": "counter", "rel": "sides", "kinds": [&"mall_register"]}, {"mode": "corner"}],
			"hide": [{"mode": "beside", "of": "counter", "rel": "sides"}, {"mode": "corner"}],
		},
		&"supermarket": {
			"steps": [
				{"op": "along", "kind": &"checkout", "side": "s", "where": "spread", "n": [2, 4], "every": 2, "tag": "till"},
				{"op": "along", "kind": &"stock_rack", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "wall"},
				{"op": "along", "kind": &"medicine_shelf", "side": "ew", "where": "spread", "n": [2, 4], "every": 1},
				{"op": "rows", "kind": &"gondola", "axis": "y", "row_gap": 1, "gap": 0, "margin": [2, 2, 2, 3], "max": 14, "tag": "aisle"},
				{"op": "decal", "mode": "near", "of": "aisle", "piece": [&"decal_boxes", &"decal_papers"], "n": 1, "jitter": 12.0},
				{"op": "art", "pieces": ["kit_wall_sale", "kit_wall_poster", "kit_wall_clock"], "density": 0.35},
			],
			"loot": [{"mode": "beside", "of": "till", "rel": "sides", "kinds": [&"mall_register", &"mall_cart"]}, {"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"stockroom": {
			"steps": [
				{"op": "along", "kind": &"stock_rack", "side": "n", "where": "spread", "n": [1, 3], "every": 1, "tag": "rack"},
				{"op": "along", "kind": &"stock_rack", "side": "ew", "where": "spread", "n": [1, 2], "every": 1, "tag": "rack"},
				{"op": "rows", "kind": &"stock_rack", "axis": "x", "row_gap": 2, "gap": 1, "margin": [1, 3, 1, 2], "max": 4, "min_room": [6, 7]},
				{"op": "corner", "kind": [&"tray_cart", &"trash_bin"], "n": [1, 2]},
				{"op": "fill", "kinds": [&"tray_cart", &"debris"], "ratio": 0.2, "max": 3},
				{"op": "decal", "mode": "scatter", "piece": [&"decal_boxes", &"decal_papers"], "n": 2, "jitter": 10.0},
				{"op": "art", "pieces": ART_BACK, "density": 0.25},
			],
			"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"mall_stock_box"]}, {"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"cinema_lobby": {
			"steps": [
				{"op": "along", "kind": &"food_counter", "side": "n", "where": "center", "n": 1, "tag": "counter"},
				{"op": "beside", "kind": &"popcorn_machine", "of": "counter", "rel": "sides", "side": &"n", "per": 1},
				{"op": "along", "kind": &"mall_sofa", "side": "ew", "where": "spread", "n": [1, 2], "every": 3},
				{"op": "corner", "kind": [&"palm_pot", &"neon_sign"], "n": 2},
				{"op": "decal", "mode": "aisle", "piece": &"decal_rug"},
				{"op": "art", "pieces": ["kit_wall_poster", "kit_wall_poster", "kit_wall_tv"], "density": 0.5},
			],
			"loot": [{"mode": "beside", "of": "counter", "rel": "sides", "kinds": [&"mall_register", &"mall_vending"]}, {"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"cinema_hall": {
			"steps": [
				{"op": "rows", "kind": &"cinema_seats", "axis": "x", "row_gap": 0, "gap": 0, "aisle": 1, "margin": [1, 1, 1, 1], "max": 20, "tag": "seats"},
				{"op": "rows", "kind": &"cinema_seats", "axis": "x", "row_gap": 0, "gap": 1, "margin": [1, 1, 1, 0], "max": 20, "tag": "seats", "unless": "seats"},
				{"op": "rows", "kind": &"food_table", "axis": "x", "row_gap": 0, "gap": 0, "margin": [1, 1, 1, 1], "max": 12, "tag": "seats", "unless": "seats"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_tray", &"decal_papers"], "n": 2, "jitter": 12.0},
				{"op": "art", "pieces": ["kit_wall_tv"], "density": 0.15},
			],
			"loot": [{"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"arcade": {
			"steps": [
				{"op": "along", "kind": &"arcade_cabinet", "side": "n", "where": "spread", "n": [4, 8], "every": 1, "tag": "cab"},
				{"op": "along", "kind": &"arcade_cabinet", "side": "ew", "where": "spread", "n": [2, 6], "every": 1, "tag": "cab"},
				{"op": "rows", "kind": &"arcade_cabinet", "axis": "x", "row_gap": 2, "gap": 0, "margin": [3, 3, 3, 3], "max": 10},
				{"op": "pillars", "n": 4, "min_room": [12, 10]},
				{"op": "corner", "kind": [&"neon_sign", &"trash_bin"], "n": 2},
				{"op": "art", "pieces": ["kit_wall_poster", "kit_wall_tv"], "density": 0.3},
			],
			"loot": [{"mode": "beside", "of": "cab", "rel": "sides", "kinds": [&"mall_vending"]}, {"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"office": {
			"steps": [
				{"op": "rows", "kind": &"office_desk", "axis": "x", "row_gap": 1, "gap": 1, "margin": [1, 1, 1, 1], "max": 4, "tag": "desk"},
				{"op": "along", "kind": &"filing_cabinet", "side": "n", "where": "spread", "n": [1, 3], "every": 1, "tag": "files"},
				{"op": "corner", "kind": [&"palm_pot"], "n": 1},
				{"op": "fill", "kinds": [&"filing_cabinet", &"palm_pot"], "ratio": 0.2, "max": 3},
				{"op": "decal", "mode": "near", "of": "desk", "piece": &"decal_papers", "n": 1, "jitter": 12.0},
				{"op": "art", "pieces": ART_OFFICE, "density": 0.45},
			],
			"loot": [{"mode": "beside", "of": "files", "rel": "sides", "kinds": [&"mall_stock_box"]}, {"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"director": {
			"steps": [
				{"op": "along", "kind": &"office_desk", "side": "n", "where": "center", "n": 1, "tag": "desk"},
				{"op": "along", "kind": &"bookshelf", "side": "n", "where": "ends", "n": [1, 2]},
				{"op": "along", "kind": &"mall_sofa", "side": "s", "n": [0, 1]},
				{"op": "corner", "kind": [&"palm_pot", &"filing_cabinet"], "n": 2},
				{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_rug", "shift": Vector2(0, 64)},
				{"op": "art", "pieces": ART_OFFICE, "density": 0.5},
			],
			"loot": [{"mode": "beside", "of": "desk", "rel": "sides"}, {"mode": "corner"}],
		},
		&"service": {
			"steps": [
				{"op": "along", "kind": &"stock_rack", "side": "n", "where": "spread", "n": [1, 2], "every": 1, "tag": "rack"},
				{"op": "along", "kind": &"tray_cart", "side": "ew", "n": [1, 2]},
				{"op": "corner", "kind": [&"trash_bin", &"debris"], "n": 2},
				{"op": "art", "pieces": ART_BACK, "density": 0.3},
			],
			"loot": [{"mode": "corner"}],
		},
		&"security": {
			"steps": [
				{"op": "along", "kind": &"tv_wall", "side": "n", "where": "spread", "n": [2, 3], "every": 1, "tag": "tv"},
				{"op": "beside", "kind": &"desk", "of": "tv", "rel": "below", "per": 1},
				{"op": "along", "kind": &"filing_cabinet", "side": "ew", "n": 1},
				{"op": "art", "pieces": ["kit_wall_board", "kit_wall_tv"], "density": 0.4},
			],
			"loot": [{"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"technical": {
			"steps": [
				{"op": "along", "kind": &"generator", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
				{"op": "along", "kind": &"stock_rack", "side": "ew", "n": [0, 1]},
				{"op": "corner", "kind": [&"trash_bin", &"debris"], "n": 2},
				{"op": "art", "pieces": ART_BACK, "density": 0.3},
			],
			"loot": [{"mode": "corner"}],
			"hide": [{"mode": "corner"}],
		},
		&"trash": {
			"steps": [
				{"op": "along", "kind": &"trash_bin", "side": "n", "where": "spread", "n": [2, 3], "every": 1},
				{"op": "corner", "kind": [&"debris"], "n": 2},
			],
			"loot": [{"mode": "corner"}],
		},
		&"vault": {
			"steps": [
				{"op": "along", "kind": &"glass_case", "side": "ew", "n": 1},
				{"op": "art", "pieces": ["kit_wall_clock"], "density": 0.3},
			],
			"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
		},
	}
	return _cache
