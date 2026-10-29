extends RefCounted
## Gabarits d'aménagement Far West par rôle de salle (Room.tags[0]) : voir furnisher.gd
## pour la syntaxe des étapes. Les meubles absents de l'atlas sont ignorés.
##
## Chaque gabarit : {"steps": [...], "loot": [emplacements des conteneurs],
## "hide": [emplacements des cachettes]} (emplacements : furnisher.place_loot).

## Compléments aux définitions de WorldProp.DEFS (collision) pour l'aménagement :
##  fp : emprise en cases (sinon déduite de la collision) ; tall : meuble haut (masque le
##  mur derrière lui : pas de décor mural) ; centered : collision centrée sur le point
##  d'appui ; gap : jeu entre la collision et le mur ; nudge : décalage visuel.
const META := {
	&"saloon_bar": {"fp": Vector2i(3, 1)},
	&"piano": {"fp": Vector2i(2, 1), "tall": true},
	&"poker_table": {"fp": Vector2i(2, 2), "nudge": Vector2(-8, 18)},
	&"counter": {"fp": Vector2i(2, 1)},
	&"desk": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"shelf": {"tall": true, "nudge": Vector2(8, 0)},
	&"bed": {"fp": Vector2i(1, 2), "gap": 2.0, "nudge": Vector2(8, 0)},
	&"pew": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"altar": {"fp": Vector2i(2, 1)},
	&"safe": {"tall": true},
	&"hay_bale": {"nudge": Vector2(8, 0)},
	&"water_trough": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"bench": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"wanted_poster": {"tall": true},
	&"support_beam": {"tall": true},
	&"mine_cart": {"nudge": Vector2(8, 0)},
	&"jail_bars": {"fp": Vector2i(1, 1)},
	&"lantern": {"visual": Vector2(20, 12)},
	&"wagon": {"fp": Vector2i(3, 1)},
	# Mobilier de l'aménagement (art/blender/build_props.py)
	&"bottle_shelf": {"fp": Vector2i(2, 1), "tall": true},
	&"stage": {"fp": Vector2i(3, 2), "visual": Vector2(180, 110)},
	&"dresser": {"tall": true},
	&"washstand": {},
	&"nightstand": {},
	&"gun_rack": {"tall": true},
	&"bookcase": {"tall": true},
	&"crate_stack": {},
	&"sacks": {},
	&"dining_table": {"fp": Vector2i(2, 2), "nudge": Vector2(0, 12)},
	&"table_chairs": {"fp": Vector2i(2, 1), "nudge": Vector2(0, 6)},
	&"candelabra": {"visual": Vector2(16, 10)},
	&"settee": {"fp": Vector2i(2, 1)},
	&"stove": {},
	&"bucket": {"visual": Vector2(20, 12)},
	&"tool_rack": {"tall": true},
	&"cart": {"fp": Vector2i(2, 1)},
	&"fence": {"fp": Vector2i(2, 1)},
}

## Décors muraux par ambiance (pièces de l'atlas, dessinées sur les faces de murs).
const ART_SALOON := ["kit_wall_frame", "kit_wall_horns", "kit_wall_mirror", "kit_wall_poster", "kit_wall_frame"]
const ART_HOME := ["kit_wall_frame", "kit_wall_clock", "kit_wall_frame", "kit_wall_mirror"]
const ART_OFFICE := ["kit_wall_frame", "kit_wall_clock", "kit_wall_poster", "kit_wall_map"]
const ART_SHERIFF := ["kit_wall_poster", "kit_wall_poster", "kit_wall_map", "kit_wall_clock"]
const ART_BARN := ["kit_wall_horns", "kit_wall_tools", "kit_wall_horseshoe"]
const ART_MINE := ["kit_wall_tools", "kit_lantern"]

const TEMPLATES := {
	# --- Saloon -------------------------------------------------------------------------
	&"saloon_hall": {
		"steps": [
			{"op": "along", "kind": &"saloon_bar", "side": "n", "where": "end", "tag": "bar"},
			{"op": "along", "kind": &"counter", "side": "ns", "where": "end", "tag": "bar", "unless": "bar"},
			{"op": "art", "above": "bar", "piece": "kit_wall_bottles"},
			{"op": "along", "kind": &"stage", "side": "n", "where": "opposite", "of": "bar", "tag": "stage", "min_room": [12, 6]},
			{"op": "beside", "kind": &"piano", "of": "stage", "rel": "sides", "side": &"n", "tag": "piano"},
			{"op": "along", "kind": &"piano", "side": "n", "where": "opposite", "of": "bar", "tag": "piano", "unless": "piano"},
			{"op": "along", "kind": &"piano", "side": "ew", "where": "end", "tag": "piano", "unless": "piano"},
			{"op": "pillars", "n": 2, "min_room": [10, 6]},
			{"op": "grid", "kind": [&"poker_table", &"poker_table", &"dining_table"], "spacing": 1, "margin": 1, "pad": 0, "ratio": 0.42, "tag": "table"},
			{"op": "grid", "kind": [&"table_chairs", &"barrel"], "alt": &"barrel", "spacing": 1, "margin": 1, "pad": 0, "ratio": 0.5, "tag": "table"},
			{"op": "island", "kind": &"poker_table", "n": [1, 2], "spacing": 1, "margin": 1, "where": "spread", "tag": "table"},
			{"op": "corner", "kind": [&"lantern", &"barrel"], "n": 2},
			{"op": "along", "kind": &"bench", "side": "ew", "n": [1, 2]},
			{"op": "fill", "kinds": [&"barrel", &"crate_stack", &"candelabra"], "ratio": 0.16, "max": 4},
			{"op": "decal", "mode": "near", "of": "bar", "piece": [&"decal_bottles", &"decal_stain"], "n": 2, "jitter": 14.0},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_cards", &"decal_bottles", &"decal_stain"], "n": 2, "jitter": 16.0},
			{"op": "decal", "mode": "near", "of": "stage", "piece": [&"decal_papers", &"decal_bottles"], "n": 2, "jitter": 12.0},
			{"op": "decal", "mode": "center", "piece": &"decal_rug", "scale": 2.0, "min_room": [10, 6]},
			{"op": "art", "pieces": ART_SALOON, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "bar", "rel": "sides", "kinds": [&"barrel", &"crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"saloon_office": {
		"steps": [
			{"op": "along", "kind": &"desk", "side": "n", "where": "center", "tag": "desk"},
			{"op": "along", "kind": &"bookcase", "side": "n", "where": "ends", "n": [1, 2], "tag": "books"},
			{"op": "corner", "kind": [&"stove", &"lantern"], "n": 1},
			{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_rug", "shift": Vector2(0, 56)},
			{"op": "decal", "mode": "near", "of": "desk", "piece": &"decal_papers", "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ART_OFFICE, "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides", "kinds": [&"cupboard", &"chest"]}, {"mode": "corner"}],
		"hide": [{"mode": "along", "side": "n"}],
	},
	&"storage": {
		"steps": [
			{"op": "along", "kind": &"shelf", "side": "n", "where": "spread", "n": [1, 3], "every": 2, "tag": "shelf"},
			{"op": "corner", "kind": [&"crate_stack", &"barrel", &"sacks"], "n": [2, 3]},
			{"op": "along", "kind": [&"crate_stack", &"sacks"], "side": "ew", "n": [1, 2]},
			{"op": "fill", "kinds": [&"crate_stack", &"barrel", &"sacks"], "ratio": 0.22, "max": 4},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_straw", &"decal_stain"], "n": 2, "jitter": 10.0},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides", "kinds": [&"crate", &"barrel"]}, {"mode": "corner"}, {"mode": "along", "side": "n"}],
		"hide": [{"mode": "corner"}],
	},
	&"gaming_room": {
		"steps": [
			{"op": "along", "kind": &"bottle_shelf", "side": "n", "where": "center", "tag": "shelf"},
			{"op": "island", "kind": &"poker_table", "n": [1, 2], "spacing": 1, "margin": 1, "tag": "table"},
			{"op": "corner", "kind": [&"lantern", &"candelabra"], "n": 1},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_cards", &"decal_bottles"], "n": 2, "jitter": 14.0},
			{"op": "art", "pieces": ART_SALOON, "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides"}, {"mode": "corner"}],
	},
	# --- Banque ---------------------------------------------------------------------------
	&"bank_hall": {
		"steps": [
			{"op": "divider", "fill": &"counter", "openings": 1, "min_room": [9, 5], "tag": "counter"},
			{"op": "along", "kind": &"counter", "side": "n", "where": "spread", "n": 2, "every": 3, "tag": "counter", "max_room": [99, 4]},
			{"op": "along", "kind": &"bench", "side": "ew", "n": [1, 2]},
			{"op": "corner", "kind": [&"lantern", &"candelabra"], "n": 1},
			{"op": "grid", "kind": &"bench", "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.28},
			{"op": "fill", "kinds": [&"bench", &"candelabra", &"safe"], "ratio": 0.18, "max": 3},
			{"op": "decal", "mode": "aisle", "piece": &"decal_runner", "vertical": true},
			{"op": "art", "pieces": ["kit_wall_frame", "kit_wall_clock", "kit_wall_poster"], "density": 0.35},
		],
		"loot": [{"mode": "along", "side": "n", "kinds": [&"cupboard"]}],
		"hide": [{"mode": "corner"}],
	},
	&"bank_office": {
		"steps": [
			{"op": "along", "kind": &"desk", "side": "n", "where": "center", "tag": "desk"},
			{"op": "along", "kind": &"bookcase", "side": "n", "where": "ends", "n": 1},
			{"op": "corner", "kind": [&"safe", &"stove"], "n": 1},
			{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_rug", "shift": Vector2(0, 56)},
			{"op": "art", "pieces": ART_OFFICE, "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides", "kinds": [&"cupboard", &"wardrobe"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"bank_vault": {
		"steps": [
			{"op": "along", "kind": &"safe", "side": "n", "where": "spread", "n": [1, 2], "every": 2, "tag": "safe"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_coins", &"decal_papers"], "n": 2, "jitter": 12.0},
		],
		"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
	},
	# --- Shérif ---------------------------------------------------------------------------
	&"sheriff_office": {
		"steps": [
			{"op": "art", "behind": "jail_cell", "piece": "kit_wall_bars"},
			{"op": "along", "kind": &"desk", "side": "ew", "where": "center", "tag": "desk", "kinds": {"e": &"desk", "w": &"desk"}},
			{"op": "along", "kind": &"gun_rack", "side": "ew", "where": "end", "n": 1, "tag": "rack"},
			{"op": "along", "kind": &"stove", "side": "ew", "n": [0, 1]},
			{"op": "pillars", "n": 2, "min_room": [10, 6]},
			{"op": "grid", "kind": &"table_chairs", "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.3, "tag": "table"},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_papers", &"decal_bottles"], "n": 1, "jitter": 12.0},
			{"op": "along", "kind": &"bench", "side": "s", "where": "spread", "n": [1, 2], "every": 3},
			{"op": "corner", "kind": [&"lantern"], "n": 1},
			{"op": "fill", "kinds": [&"crate_stack", &"bench", &"barrel", &"stove"], "ratio": 0.16, "max": 4},
			{"op": "decal", "mode": "under", "of": "table", "piece": &"decal_rug_round", "shift": Vector2(0, 8)},
			{"op": "decal", "mode": "near", "of": "desk", "piece": &"decal_papers", "n": 2, "jitter": 14.0},
			{"op": "art", "pieces": ART_SHERIFF, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"cupboard", &"chest"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"jail_cell": {
		"steps": [
			{"op": "along", "kind": &"bed", "side": "ew", "where": "end", "tag": "bed"},
			{"op": "corner", "kind": &"bucket", "n": 1},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_straw", &"decal_stain"], "n": 2, "jitter": 12.0},
		],
		"loot": [{"mode": "beside", "of": "bed", "rel": "foot"}, {"mode": "corner"}],
	},
	&"sheriff_armory": {
		"steps": [
			{"op": "along", "kind": &"gun_rack", "side": "n", "where": "spread", "n": [1, 2], "every": 1, "tag": "rack"},
			{"op": "along", "kind": &"crate_stack", "side": "ew", "n": 1},
			{"op": "art", "pieces": ["kit_wall_rifles"], "density": 0.6},
		],
		"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
	},
	# --- Magasin --------------------------------------------------------------------------
	&"store_shop": {
		"steps": [
			{"op": "along", "kind": &"shelf", "side": "n", "where": "spread", "n": [2, 4], "every": 2, "tag": "shelf"},
			{"op": "along", "kind": &"counter", "side": "ew", "where": "center", "tag": "counter", "kinds": {"e": &"counter", "w": &"counter"}},
			{"op": "corner", "kind": [&"barrel", &"sacks", &"crate_stack"], "n": [1, 2]},
			{"op": "rows", "kind": &"shelf", "axis": "x", "row_gap": 2, "margin": [2, 3, 2, 1], "max": 3, "min_room": [9, 5]},
			{"op": "grid", "kind": [&"barrel", &"sacks", &"crate_stack"], "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.3},
			{"op": "fill", "kinds": [&"barrel", &"sacks", &"crate_stack"], "ratio": 0.18, "max": 4},
			{"op": "decal", "mode": "near", "of": "shelf", "piece": [&"decal_papers", &"decal_straw"], "n": 1, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_poster", "kit_wall_clock", "kit_wall_tools"], "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "counter", "rel": "sides", "kinds": [&"barrel", &"crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"office": {
		"steps": [
			{"op": "along", "kind": &"desk", "side": "n", "where": "center", "tag": "desk"},
			{"op": "along", "kind": &"bookcase", "side": "n", "where": "ends", "n": 1},
			{"op": "corner", "kind": [&"stove", &"lantern"], "n": 1},
			{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_rug", "shift": Vector2(0, 56)},
			{"op": "art", "pieces": ART_OFFICE, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides", "kinds": [&"cupboard", &"wardrobe"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	# --- Hôtel ----------------------------------------------------------------------------
	&"hotel_reception": {
		"steps": [
			{"op": "along", "kind": &"counter", "side": "n", "where": "end", "tag": "desk"},
			{"op": "art", "above": "desk", "piece": "kit_wall_keys"},
			{"op": "along", "kind": &"settee", "side": "n", "where": "opposite", "of": "desk", "n": 1, "tag": "settee"},
			{"op": "beside", "kind": &"nightstand", "of": "settee", "rel": "sides", "side": &"n"},
			{"op": "along", "kind": &"bench", "side": "ew", "n": [0, 1]},
			{"op": "corner", "kind": [&"lantern", &"candelabra"], "n": 1},
			{"op": "grid", "kind": &"table_chairs", "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.3, "tag": "lounge"},
			{"op": "decal", "mode": "under", "of": "lounge", "piece": &"decal_rug_round", "n": 3, "shift": Vector2(0, 8)},
			{"op": "fill", "kinds": [&"candelabra", &"nightstand", &"bench", &"barrel"], "ratio": 0.13, "max": 4},
			{"op": "decal", "mode": "aisle", "piece": &"decal_runner"},
			{"op": "art", "pieces": ART_HOME, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides", "kinds": [&"cupboard", &"chest"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"hotel_dining": {
		"steps": [
			{"op": "along", "kind": &"dresser", "side": "n", "where": "center", "tag": "sideboard"},
			{"op": "grid", "kind": &"dining_table", "spacing": 1, "margin": 1, "pad": 0, "ratio": 0.3, "tag": "table"},
			{"op": "island", "kind": &"dining_table", "n": [1, 2], "spacing": 1, "margin": 1, "tag": "table"},
			{"op": "island", "kind": &"table_chairs", "n": [1, 2], "spacing": 1, "margin": 1, "tag": "table"},
			{"op": "corner", "kind": [&"candelabra", &"lantern"], "n": 1},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_bottles", &"decal_stain"], "n": 1, "jitter": 14.0},
			{"op": "art", "pieces": ART_HOME, "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "sideboard", "rel": "sides", "kinds": [&"cupboard", &"barrel"]}, {"mode": "corner"}],
	},
	&"corridor": {
		"steps": [
			{"op": "decal", "mode": "aisle", "piece": &"decal_runner"},
			{"op": "art", "pieces": ART_HOME, "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
	},
	&"upper_corridor": {
		"steps": [
			{"op": "decal", "mode": "aisle", "piece": &"decal_runner"},
			{"op": "art", "pieces": ART_HOME, "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
	},
	&"bedroom": {
		"steps": [
			{"op": "along", "kind": &"bed", "side": "n", "where": "end", "tag": "bed"},
			{"op": "beside", "kind": &"nightstand", "of": "bed", "rel": "sides", "side": &"n", "per": 1, "tag": "night"},
			{"op": "art", "above": "bed", "piece": "kit_wall_frame"},
			{"op": "along", "kind": [&"dresser", &"washstand"], "side": "n", "where": "opposite", "of": "bed", "n": 1, "tag": "dresser"},
			{"op": "along", "kind": &"washstand", "side": "ew", "n": [0, 1], "min_room": [4, 4]},
			{"op": "island", "kind": &"table_chairs", "n": 1, "margin": 1, "spacing": 1, "min_room": [5, 6], "where": "spread"},
			{"op": "fill", "kinds": [&"candelabra", &"washstand", &"nightstand", &"bucket"], "ratio": 0.14, "max": 3},
			{"op": "decal", "mode": "under", "of": "bed", "piece": &"decal_rug_round", "shift": Vector2(0, 70)},
			{"op": "art", "pieces": ART_HOME, "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "bed", "rel": "foot", "kinds": [&"chest"]}, {"mode": "corner", "kinds": [&"wardrobe", &"cupboard"]}],
		"hide": [{"mode": "corner"}, {"mode": "along", "side": "n"}],
	},
	&"suite": {
		"steps": [
			{"op": "along", "kind": &"bed", "side": "n", "where": "center", "tag": "bed"},
			{"op": "beside", "kind": &"nightstand", "of": "bed", "rel": "sides", "side": &"n", "per": 2},
			{"op": "art", "above": "bed", "piece": "kit_wall_frame"},
			{"op": "along", "kind": &"dresser", "side": "ew", "n": 1},
			{"op": "along", "kind": &"desk", "side": "ew", "n": [0, 1], "min_room": [5, 5]},
			{"op": "corner", "kind": [&"candelabra"], "n": 1},
			{"op": "decal", "mode": "under", "of": "bed", "piece": &"decal_rug", "shift": Vector2(0, 80)},
			{"op": "art", "pieces": ART_HOME, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "bed", "rel": "foot", "kinds": [&"chest"]}, {"mode": "corner"}, {"mode": "along", "side": "n"}],
	},
	# --- Écurie ---------------------------------------------------------------------------
	&"stable_main": {
		"steps": [
			{"op": "stalls", "side": "n", "len": 2, "spacing": 2, "n": [2, 3], "min_room": [10, 5]},
			{"op": "stalls", "side": "n", "len": 1, "spacing": 2, "n": [2, 4], "min_room": [10, 3], "max_room": [99, 4]},
			{"op": "along", "kind": &"hay_bale", "side": "n", "where": "spread", "n": [2, 3], "every": 2, "tag": "hay"},
			{"op": "along", "kind": &"water_trough", "side": "ew", "n": 1},
			{"op": "corner", "kind": [&"hay_bale", &"bucket", &"sacks"], "n": [1, 2]},
			{"op": "island", "kind": &"wagon", "n": [0, 1], "margin": 1, "spacing": 1, "min_room": [12, 5], "chance": 0.6},
			{"op": "grid", "kind": [&"hay_bale", &"barrel", &"sacks"], "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.3},
			{"op": "along", "kind": [&"hay_bale", &"sacks", &"crate_stack"], "side": "s", "where": "spread", "n": [2, 4], "every": 2},
			{"op": "fill", "kinds": [&"hay_bale", &"barrel", &"bucket", &"sacks"], "ratio": 0.2, "max": 6},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_straw", &"decal_straw", &"decal_hoofprints"], "n": 8, "jitter": 14.0},
			{"op": "art", "pieces": ART_BARN, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "hay", "rel": "sides", "kinds": [&"crate", &"barrel"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}, {"mode": "along", "side": "n"}],
	},
	&"stable_box": {
		"steps": [
			{"op": "along", "kind": &"water_trough", "side": "n", "where": "end", "n": 1, "tag": "trough"},
			{"op": "corner", "kind": [&"hay_bale"], "n": 1, "tag": "hay"},
			{"op": "corner", "kind": [&"bucket"], "n": [0, 1]},
			{"op": "decal", "mode": "scatter", "piece": &"decal_straw", "n": 5, "jitter": 14.0},
		],
		"loot": [{"mode": "corner", "kinds": [&"crate", &"barrel"]}],
		"hide": [{"mode": "corner"}],
	},
	# --- Église ---------------------------------------------------------------------------
	&"church_nave": {
		"steps": [
			{"op": "along", "kind": &"altar", "side": "n", "where": "center", "tag": "altar"},
			{"op": "beside", "kind": &"candelabra", "of": "altar", "rel": "sides", "side": &"n", "per": 2},
			{"op": "art", "above": "altar", "piece": "kit_wall_cross"},
			{"op": "rows", "kind": &"pew", "axis": "x", "row_gap": 0, "aisle": 1, "margin": [0, 2, 0, 1]},
			{"op": "decal", "mode": "aisle", "piece": &"decal_runner", "vertical": true, "skip_start": 1},
			{"op": "art", "pieces": ["kit_wall_frame", "kit_wall_cross"], "density": 0.25},
		],
		"loot": [{"mode": "corner"}],
	},
	&"church_sacristy": {
		"steps": [
			{"op": "along", "kind": &"bookcase", "side": "n", "where": "end", "n": 1, "tag": "books"},
			{"op": "along", "kind": &"table_chairs", "side": "n", "where": "opposite", "of": "books", "n": 1},
			{"op": "corner", "kind": [&"candelabra"], "n": 1},
			{"op": "art", "pieces": ["kit_wall_cross", "kit_wall_frame"], "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "books", "rel": "sides", "kinds": [&"wardrobe", &"chest"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	# --- Cabanes de la ville éparpillée ------------------------------------------------
	&"shack": {
		"steps": [
			{"op": "along", "kind": [&"bed", &"shelf", &"dresser"], "side": "n", "where": "end", "tag": "main"},
			{"op": "along", "kind": [&"stove", &"tool_rack", &"bookcase"], "side": "n", "where": "opposite", "of": "main", "n": 1},
			{"op": "island", "kind": &"table_chairs", "n": 1, "margin": 1, "spacing": 1, "min_room": [4, 3], "tag": "table"},
			{"op": "corner", "kind": [&"barrel", &"crate_stack", &"sacks", &"bucket", &"lantern"], "n": [1, 2]},
			{"op": "fill", "kinds": [&"barrel", &"sacks", &"bucket", &"crate_stack"], "ratio": 0.2, "max": 3},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_bottles", &"decal_papers", &"decal_cards"], "n": 1, "jitter": 12.0},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_straw", &"decal_stain"], "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ART_HOME, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "main", "rel": "sides", "kinds": [&"cupboard", &"chest"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	# --- Appentis, remises, latrines collés aux maisons ---------------------------------
	&"shed": {
		"steps": [
			{"op": "corner", "kind": [&"crate_stack", &"barrel", &"sacks", &"tool_rack", &"bucket"], "n": [1, 2], "tag": "main"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_straw", &"decal_stain"], "n": 1, "jitter": 12.0},
		],
		"loot": [{"mode": "corner", "kinds": [&"crate", &"barrel", &"chest"]}],
		"hide": [{"mode": "corner"}],
	},
	# --- Mine -----------------------------------------------------------------------------
	&"mine_entrance": {
		"steps": [
			{"op": "decal", "mode": "rails", "piece": &"prop_rail_track"},
			{"op": "along", "kind": &"support_beam", "side": "ew", "where": "spread", "n": [2, 4], "every": 2},
			{"op": "along", "kind": &"mine_cart", "side": "n", "where": "end", "n": 1, "tag": "cart"},
			{"op": "corner", "kind": [&"crate_stack", &"ore_pile", &"lantern"], "n": [1, 2]},
			{"op": "grid", "kind": [&"crate_stack", &"ore_pile", &"barrel"], "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.28},
			{"op": "art", "pieces": ART_MINE, "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "cart", "rel": "sides", "kinds": [&"crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"mine_tools": {
		"steps": [
			{"op": "along", "kind": &"tool_rack", "side": "n", "where": "end", "n": 1, "tag": "rack"},
			{"op": "along", "kind": [&"crate_stack", &"sacks"], "side": "ew", "n": [1, 2]},
			{"op": "art", "pieces": ["kit_wall_tools"], "density": 0.5},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"mine_entry": {
		"steps": [
			{"op": "decal", "mode": "rails", "piece": &"prop_rail_track"},
			{"op": "along", "kind": &"support_beam", "side": "ew", "where": "spread", "n": [2, 2], "every": 2},
			{"op": "along", "kind": &"mine_cart", "side": "n", "where": "end", "n": 1, "tag": "cart"},
			{"op": "corner", "kind": [&"lantern", &"crate_stack"], "n": 1},
		],
		"loot": [{"mode": "corner"}],
	},
	&"ore_room": {
		"steps": [
			{"op": "decal", "mode": "rails", "piece": &"prop_rail_track", "chance": 0.7},
			{"op": "along", "kind": &"support_beam", "side": "ew", "where": "spread", "n": [2, 4], "every": 2},
			{"op": "corner", "kind": [&"ore_pile", &"ore_pile", &"lantern", &"crate_stack"], "n": [2, 3], "tag": "pile"},
			{"op": "along", "kind": &"mine_cart", "side": "n", "n": [0, 1], "tag": "cart"},
			{"op": "grid", "kind": [&"ore_pile", &"support_beam", &"crate_stack"], "spacing": 2, "margin": 1, "pad": 1, "ratio": 0.28},
			{"op": "fill", "kinds": [&"ore_pile", &"crate_stack", &"barrel"], "ratio": 0.2, "max": 3},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_pebbles_0", &"decal_pebbles_1"], "n": 3, "jitter": 14.0},
		],
		"loot": [{"mode": "beside", "of": "cart", "rel": "sides"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
}
