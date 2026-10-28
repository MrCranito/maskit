extends RefCounted
## Gabarits d'aménagement de la Station Orbitale par rôle de salle (Room.tags[0]) : syntaxe des
## étapes dans scripts/dungeon/gen/furnisher.gd. Les meubles absents de l'atlas sont ignorés.
## Les grandes salles (hangar, réacteur, passerelle) gardent leur pièce maîtresse (navette, cœur)
## posée par ss_populator avant l'aménagement.

## Compléments aux définitions de collision de ss_prop.gd (fp : emprise en cases ; tall : meuble
## haut, masque le mur derrière lui ; nudge : décalage visuel).
const META := {
	&"console": {"fp": Vector2i(2, 1)},
	&"server_rack": {"tall": true},
	&"bunk_bed": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"mess_table": {"fp": Vector2i(2, 2), "nudge": Vector2(-8, 10)},
	&"med_bed": {"fp": Vector2i(1, 1), "nudge": Vector2(12, 0)},
	&"lab_bench": {"fp": Vector2i(2, 1)},
	&"specimen_tank": {"tall": true},
	&"pipe_cluster": {"tall": true, "fp": Vector2i(1, 1)},
	&"holo_table": {},
	&"weapon_rack": {"fp": Vector2i(2, 1), "tall": true},
	&"plant_bed": {"fp": Vector2i(2, 1)},
	&"vending_machine": {"tall": true},
	&"coolant_tank": {"tall": true},
	&"workbench": {"fp": Vector2i(2, 1)},
	&"warning_beacon": {"visual": Vector2(14, 10)},
	# Mobilier de l'aménagement (art/blender/space_station/build_furniture.py)
	&"desk_station": {"fp": Vector2i(2, 2)},
	&"locker_bank": {"fp": Vector2i(2, 1), "tall": true},
	&"supply_shelf": {"fp": Vector2i(2, 1), "tall": true},
	&"crew_table": {"fp": Vector2i(2, 2), "nudge": Vector2(-6, 8)},
	&"med_cabinet_wall": {"tall": true, "nudge": Vector2(12, 0)},
	&"tool_wall": {"fp": Vector2i(2, 1), "tall": true},
	&"crate_pallet": {"fp": Vector2i(1, 1), "nudge": Vector2(8, 0)},
	&"bio_bed": {"fp": Vector2i(1, 2), "tall": true, "nudge": Vector2(12, 0)},
	&"ss_planter": {},
	&"ss_chair": {"visual": Vector2(24, 14)},
}

const ART_DECK := ["kit_wall_screen", "kit_wall_vent", "kit_wall_sign", "kit_wall_panel"]
const ART_HULL := ["kit_wall_window", "kit_wall_screen", "kit_wall_window", "kit_wall_vent"]
const ART_MACHINE := ["kit_wall_pipes", "kit_wall_panel", "kit_wall_vent", "kit_wall_sign"]

## Aménagement commun des salles techniques (réutilisé par plusieurs rôles).
const _MACHINE_STEPS := [
	{"op": "along", "kind": &"pipe_cluster", "side": "n", "where": "spread", "n": [2, 3], "every": 2},
	{"op": "along", "kind": &"coolant_tank", "side": "ew", "where": "spread", "n": [1, 2], "every": 2},
	{"op": "pillars", "n": 2, "min_room": [9, 7]},
	{"op": "corner", "kind": [&"power_node", &"fuel_drums", &"warning_beacon"], "n": [1, 2]},
	{"op": "along", "kind": &"power_node", "side": "ew", "where": "spread", "n": [1, 2], "every": 3},
	{"op": "fill", "kinds": [&"fuel_drums", &"crate_pallet", &"warning_beacon", &"coolant_tank"], "ratio": 0.18, "max": 5},
	{"op": "decal", "mode": "scatter", "piece": [&"decal_oil", &"decal_cables", &"decal_hazard"], "n": 3, "jitter": 10.0},
	{"op": "art", "pieces": ART_MACHINE, "density": 0.35},
]

const TEMPLATES := {
	&"quarters": {
		"steps": [
			{"op": "along", "kind": &"bunk_bed", "side": "n", "where": "spread", "n": [2, 4], "every": 2, "tag": "bunk"},
			{"op": "along", "kind": &"bunk_bed", "side": "ew", "where": "spread", "n": [2, 4], "every": 2, "tag": "bunk", "min_room": [4, 6]},
			{"op": "along", "kind": &"locker_bank", "side": "s", "where": "end", "n": 1, "tag": "lockers"},
			{"op": "along", "kind": &"locker_bank", "side": "ew", "where": "end", "n": 1, "tag": "lockers", "unless": "lockers"},
			{"op": "island", "kind": &"crew_table", "n": 1, "margin": 1, "spacing": 1, "min_room": [6, 6], "tag": "table"},
			{"op": "corner", "kind": [&"ss_planter", &"vending_machine"], "n": 1},
			{"op": "fill", "kinds": [&"ss_planter", &"ss_chair", &"crate_pallet", &"vending_machine"], "ratio": 0.2, "max": 5},
			{"op": "decal", "mode": "near", "of": "table", "piece": &"decal_tablet", "n": 1, "jitter": 12.0},
			{"op": "decal", "mode": "under", "of": "bunk", "piece": &"decal_mat", "n": 2, "shift": Vector2(0, 56)},
			{"op": "art", "pieces": ART_HULL, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "bunk", "rel": "sides", "kinds": [&"locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "beside", "of": "lockers", "rel": "sides"}, {"mode": "corner"}],
	},
	&"officer_quarters": {
		"steps": [
			{"op": "along", "kind": &"bio_bed", "side": "n", "where": "end", "n": [1, 2], "tag": "bunk"},
			{"op": "along", "kind": &"desk_station", "side": "n", "where": "opposite", "of": "bunk", "n": 1, "tag": "desk"},
			{"op": "along", "kind": &"locker_bank", "side": "ew", "n": 1, "tag": "lockers"},
			{"op": "corner", "kind": [&"ss_planter"], "n": 1},
			{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_mat", "shift": Vector2(0, 48)},
			{"op": "art", "pieces": ART_HULL, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "lockers", "rel": "sides", "kinds": [&"locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"captain_cabin": {
		"steps": [
			{"op": "along", "kind": &"bio_bed", "side": "n", "where": "end", "n": 1, "tag": "bunk"},
			{"op": "along", "kind": &"desk_station", "side": "n", "where": "opposite", "of": "bunk", "n": 1, "tag": "desk"},
			{"op": "island", "kind": &"holo_table", "n": 1, "margin": 2, "min_room": [7, 7]},
			{"op": "corner", "kind": [&"ss_planter", &"plant_bed"], "n": 2},
			{"op": "decal", "mode": "under", "of": "desk", "piece": &"decal_mat", "shift": Vector2(0, 48)},
			{"op": "art", "pieces": ART_HULL, "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides"}, {"mode": "corner"}],
	},
	&"mess_hall": {
		"steps": [
			{"op": "along", "kind": &"vending_machine", "side": "n", "where": "spread", "n": [2, 3], "every": 2, "tag": "vend"},
			{"op": "along", "kind": &"vending_machine", "side": "ew", "where": "spread", "n": [1, 2], "every": 3, "tag": "vend"},
			{"op": "rows", "kind": &"mess_table", "axis": "x", "row_gap": 1, "gap": 0, "margin": [1, 2, 1, 1], "max": 8, "tag": "table"},
			{"op": "corner", "kind": [&"ss_planter"], "n": 2},
			{"op": "fill", "kinds": [&"ss_planter", &"crate_pallet", &"supply_shelf"], "ratio": 0.18, "max": 4},
			{"op": "decal", "mode": "near", "of": "table", "piece": &"decal_tablet", "n": 1, "jitter": 14.0},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "vend", "rel": "sides"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"infirmary": {
		"steps": [
			{"op": "along", "kind": &"med_bed", "side": "n", "where": "spread", "n": [2, 4], "every": 2, "tag": "bed"},
			{"op": "along", "kind": &"med_bed", "side": "ew", "where": "spread", "n": [1, 3], "every": 2, "tag": "bed"},
			{"op": "along", "kind": &"med_cabinet_wall", "side": "ew", "where": "spread", "n": [1, 2], "every": 2, "tag": "cab"},
			{"op": "booth", "w": 2, "h": 2, "fill": &"specimen_tank", "min_room": [9, 6]},
			{"op": "island", "kind": &"desk_station", "n": 1, "margin": 1, "spacing": 1, "where": "end", "min_room": [8, 6]},
			{"op": "corner", "kind": [&"ss_planter"], "n": 1},
			{"op": "decal", "mode": "near", "of": "bed", "piece": [&"decal_tablet", &"decal_papers"], "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ["kit_wall_screen", "kit_wall_panel", "kit_wall_sign"], "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "cab", "rel": "sides", "kinds": [&"med_cabinet"]}, {"mode": "in", "of": "booth"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"lab": {
		"steps": [
			{"op": "along", "kind": &"lab_bench", "side": "n", "where": "spread", "n": [2, 3], "every": 3, "tag": "bench"},
			{"op": "along", "kind": &"specimen_tank", "side": "ew", "where": "spread", "n": [1, 3], "every": 2, "tag": "tank"},
			{"op": "booth", "w": 2, "h": 2, "fill": &"server_rack", "min_room": [10, 6]},
			{"op": "rows", "kind": &"lab_bench", "axis": "x", "row_gap": 2, "gap": 1, "margin": [2, 3, 2, 2], "max": 2, "min_room": [9, 8]},
			{"op": "island", "kind": &"holo_table", "n": 1, "margin": 2, "min_room": [8, 6]},
			{"op": "along", "kind": &"lab_bench", "side": "ew", "where": "spread", "n": [1, 2], "every": 3, "tag": "bench", "min_room": [4, 7]},
			{"op": "fill", "kinds": [&"ss_chair", &"specimen_tank", &"med_cabinet_wall", &"server_rack"], "ratio": 0.18, "max": 5},
			{"op": "decal", "mode": "near", "of": "bench", "piece": [&"decal_papers", &"decal_coolant"], "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ["kit_wall_screen", "kit_wall_panel", "kit_wall_window"], "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "bench", "rel": "sides", "kinds": [&"terminal", &"med_cabinet"]}, {"mode": "in", "of": "booth"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"lab_vault": {
		"steps": [
			{"op": "along", "kind": &"specimen_tank", "side": "n", "where": "spread", "n": [2, 3], "every": 2, "tag": "tank"},
			{"op": "along", "kind": &"lab_bench", "side": "ew", "n": 1},
			{"op": "art", "pieces": ["kit_wall_screen", "kit_wall_panel"], "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "tank", "rel": "sides"}, {"mode": "corner"}],
	},
	&"storage": {
		"steps": [
			{"op": "along", "kind": &"supply_shelf", "side": "n", "where": "spread", "n": [2, 3], "every": 1, "tag": "shelf"},
			{"op": "rows", "kind": &"supply_shelf", "axis": "x", "row_gap": 2, "gap": 1, "margin": [1, 3, 1, 2], "max": 4, "min_room": [7, 7]},
			{"op": "along", "kind": &"supply_shelf", "side": "ew", "where": "spread", "n": [1, 3], "every": 1, "tag": "shelf"},
			{"op": "corner", "kind": [&"crate_pallet", &"cargo_stack", &"fuel_drums"], "n": [2, 3]},
			{"op": "fill", "kinds": [&"crate_pallet", &"cargo_stack", &"fuel_drums"], "ratio": 0.26, "max": 6},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_oil", &"decal_arrow"], "n": 2, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_sign", "kit_wall_vent"], "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides", "kinds": [&"cargo_crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"cargo_hold": {
		"steps": [
			{"op": "rows", "kind": &"cargo_stack", "axis": "x", "row_gap": 2, "gap": 1, "margin": [1, 1, 1, 1], "max": 8},
			{"op": "corner", "kind": [&"crate_pallet", &"fuel_drums"], "n": [2, 3]},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_hazard", &"decal_arrow", &"decal_oil"], "n": 3, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_sign", "kit_wall_vent", "kit_wall_pipes"], "density": 0.3},
		],
		"loot": [{"mode": "corner"}, {"mode": "along", "side": "n"}],
		"hide": [{"mode": "corner"}],
	},
	&"workshop": {
		"steps": [
			{"op": "along", "kind": &"workbench", "side": "n", "where": "spread", "n": [1, 2], "every": 3, "tag": "bench"},
			{"op": "along", "kind": &"tool_wall", "side": "n", "where": "opposite", "of": "bench", "n": 1, "tag": "tools"},
			{"op": "along", "kind": &"power_node", "side": "ew", "n": [0, 1]},
			{"op": "island", "kind": &"workbench", "n": [0, 1], "margin": 1, "spacing": 1, "min_room": [9, 7]},
			{"op": "along", "kind": &"tool_wall", "side": "ew", "where": "spread", "n": [1, 2], "every": 3, "tag": "tools"},
			{"op": "corner", "kind": [&"crate_pallet", &"fuel_drums"], "n": [1, 2]},
			{"op": "fill", "kinds": [&"crate_pallet", &"ss_chair", &"fuel_drums", &"power_node"], "ratio": 0.18, "max": 5},
			{"op": "decal", "mode": "near", "of": "bench", "piece": [&"decal_tools", &"decal_oil"], "n": 2, "jitter": 12.0},
			{"op": "art", "pieces": ART_MACHINE, "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "bench", "rel": "sides", "kinds": [&"cargo_crate", &"locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"server_room": {
		"steps": [
			{"op": "along", "kind": &"server_rack", "side": "n", "where": "spread", "n": [3, 5], "every": 1, "tag": "rack"},
			{"op": "rows", "kind": &"server_rack", "axis": "x", "row_gap": 2, "gap": 0, "margin": [1, 3, 1, 2], "max": 6, "min_room": [6, 7]},
			{"op": "along", "kind": &"console", "side": "ew", "n": 1, "tag": "console"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_cables"], "n": 3, "jitter": 8.0},
			{"op": "art", "pieces": ["kit_wall_panel", "kit_wall_vent"], "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "console", "rel": "sides", "kinds": [&"terminal"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"hydroponics": {
		"steps": [
			{"op": "rows", "kind": &"plant_bed", "axis": "x", "row_gap": 1, "gap": 0, "margin": [1, 1, 1, 1], "max": 10},
			{"op": "along", "kind": &"pipe_cluster", "side": "n", "n": [0, 1]},
			{"op": "corner", "kind": [&"ss_planter"], "n": 2},
			{"op": "fill", "kinds": [&"ss_planter", &"crate_pallet"], "ratio": 0.2, "max": 3},
			{"op": "art", "pieces": ["kit_wall_pipes", "kit_wall_panel"], "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"closet": {
		"steps": [
			{"op": "along", "kind": &"supply_shelf", "side": "n", "n": 1, "tag": "shelf"},
			{"op": "corner", "kind": [&"crate_pallet", &"cargo_stack"], "n": 1},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"bridge": {
		"steps": [
			{"op": "along", "kind": &"console", "side": "n", "where": "spread", "n": [4, 7], "every": 2, "tag": "console"},
			{"op": "beside", "kind": &"ss_chair", "of": "console", "rel": "below", "per": 1},
			{"op": "pillars", "n": 4, "min_room": [14, 9]},
			{"op": "rows", "kind": &"desk_station", "axis": "x", "row_gap": 1, "gap": 1, "aisle": 3, "margin": [2, 3, 2, 3], "max": 12, "min_room": [12, 9]},
			{"op": "island", "kind": &"captain_chair", "n": 1, "margin": 2, "where": "north"},
			{"op": "island", "kind": &"holo_table", "n": [1, 2], "margin": 2, "spacing": 3},
			{"op": "along", "kind": &"server_rack", "side": "ew", "where": "spread", "n": [2, 4], "every": 2},
			{"op": "along", "kind": [&"locker_bank", &"supply_shelf"], "side": "s", "where": "spread", "n": [1, 3], "every": 4},
			{"op": "fill", "kinds": [&"ss_planter", &"server_rack", &"crate_pallet"], "ratio": 0.12, "max": 6},
			{"op": "corner", "kind": [&"ss_planter"], "n": 2},
			{"op": "decal", "mode": "aisle", "piece": &"decal_lightstrip", "vertical": true},
			{"op": "art", "pieces": ART_HULL, "density": 0.4},
		],
		"loot": [{"mode": "corner"}, {"mode": "beside", "of": "console", "rel": "sides", "kinds": [&"terminal"]}],
	},
	&"radar": {
		"steps": [
			{"op": "island", "kind": &"holo_table", "n": 1, "margin": 2},
			{"op": "along", "kind": &"console", "side": "n", "where": "spread", "n": [2, 3], "every": 2, "tag": "console"},
			{"op": "beside", "kind": &"ss_chair", "of": "console", "rel": "below", "per": 1},
			{"op": "along", "kind": &"server_rack", "side": "ew", "n": [1, 2]},
			{"op": "art", "pieces": ART_HULL, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "console", "rel": "sides", "kinds": [&"terminal"]}, {"mode": "corner"}],
	},
	&"comms": {
		"steps": [
			{"op": "along", "kind": &"console", "side": "n", "where": "spread", "n": [2, 3], "every": 2, "tag": "console"},
			{"op": "beside", "kind": &"ss_chair", "of": "console", "rel": "below", "per": 1},
			{"op": "along", "kind": &"server_rack", "side": "ew", "where": "spread", "n": [1, 3], "every": 1},
			{"op": "fill", "kinds": [&"server_rack", &"ss_chair", &"ss_planter"], "ratio": 0.16, "max": 4},
			{"op": "rows", "kind": &"desk_station", "axis": "x", "row_gap": 1, "gap": 1, "margin": [2, 3, 2, 2], "max": 4, "min_room": [9, 8]},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_cables", &"decal_papers"], "n": 2, "jitter": 10.0},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "console", "rel": "sides", "kinds": [&"terminal"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"armory": {
		"steps": [
			{"op": "along", "kind": &"weapon_rack", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "rack"},
			{"op": "along", "kind": &"locker_bank", "side": "ew", "n": [1, 2], "tag": "lockers"},
			{"op": "island", "kind": &"workbench", "n": [0, 1], "margin": 1, "min_room": [6, 6]},
			{"op": "art", "pieces": ["kit_wall_sign", "kit_wall_panel"], "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"armory_chest"]}, {"mode": "corner"}],
	},
	&"briefing": {
		"steps": [
			{"op": "along", "kind": &"console", "side": "n", "where": "center", "n": 1, "tag": "screen"},
			{"op": "island", "kind": &"holo_table", "n": 1, "margin": 2, "where": "north"},
			{"op": "rows", "kind": &"ss_chair", "axis": "x", "row_gap": 1, "gap": 0, "margin": [1, 4, 1, 1], "max": 12},
			{"op": "along", "kind": &"locker_bank", "side": "ew", "n": [0, 1], "tag": "lockers"},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"observatory": {
		"steps": [
			{"op": "rows", "kind": &"captain_chair", "axis": "x", "row_gap": 1, "gap": 1, "margin": [1, 2, 1, 2], "max": 4},
			{"op": "corner", "kind": [&"ss_planter", &"plant_bed"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_window"], "density": 0.7},
		],
		"loot": [{"mode": "corner"}],
	},
	&"pumps": {"steps": _MACHINE_STEPS, "loot": [{"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"coolant": {"steps": _MACHINE_STEPS, "loot": [{"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"generator": {"steps": _MACHINE_STEPS, "loot": [{"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"maintenance_pod": {
		"steps": [
			{"op": "along", "kind": &"escape_pod", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
			{"op": "along", "kind": &"tool_wall", "side": "ew", "n": 1},
			{"op": "corner", "kind": [&"crate_pallet", &"warning_beacon"], "n": 2},
			{"op": "art", "pieces": ART_MACHINE, "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
	},
	&"core_vault": {
		"steps": [
			{"op": "along", "kind": &"power_node", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
			{"op": "corner", "kind": [&"coolant_tank"], "n": 1},
			{"op": "art", "pieces": ART_MACHINE, "density": 0.4},
		],
		"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
	},
}
