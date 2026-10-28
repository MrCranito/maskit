extends RefCounted
## Gabarits d'aménagement de la station sous-marine par rôle de module (Room.tags[0]) : syntaxe
## des étapes dans scripts/dungeon/gen/furnisher.gd. Les tubes vitrés et passerelles gardent
## l'ameublement par règles de uw_populator.gd (coraux, vannes).

## Compléments aux définitions de collision de underwater_prop.gd (fp : emprise en cases ; tall :
## meuble haut, masque le mur derrière lui ; nudge : décalage visuel).
const META := {
	&"console": {"fp": Vector2i(1, 1), "nudge": Vector2(12, 0)},
	&"server_rack": {"tall": true},
	&"bunk_bed": {"fp": Vector2i(1, 1), "nudge": Vector2(14, 0)},
	&"mess_table": {"fp": Vector2i(1, 1), "nudge": Vector2(12, 0)},
	&"med_bed": {"fp": Vector2i(2, 1)},
	&"aquarium_tank": {"fp": Vector2i(1, 1), "tall": true, "nudge": Vector2(10, 0)},
	&"specimen_tank": {"tall": true},
	&"lab_bench": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"pipes": {"tall": true},
	&"pump": {"fp": Vector2i(1, 1), "nudge": Vector2(12, 0)},
	&"oxygen_rack": {"fp": Vector2i(1, 1), "tall": true, "nudge": Vector2(12, 0)},
	&"diving_suit": {"tall": true},
	&"generator": {"fp": Vector2i(2, 1)},
	&"hydro_planter": {"fp": Vector2i(1, 1), "nudge": Vector2(16, 0)},
	&"desk": {"fp": Vector2i(1, 1), "nudge": Vector2(10, 0)},
	&"crate_stack": {"fp": Vector2i(1, 1), "nudge": Vector2(8, 0)},
	&"lamp_post": {"visual": Vector2(10, 8)},
	&"alarm_light": {"visual": Vector2(10, 8)},
	# Mobilier de l'aménagement (art/blender/underwater/uw_furniture.py)
	&"uw_locker_bank": {"fp": Vector2i(2, 1), "tall": true},
	&"uw_bunk": {"fp": Vector2i(1, 2), "tall": true, "nudge": Vector2(4, 0)},
	&"uw_table": {"fp": Vector2i(2, 1), "nudge": Vector2(10, 0)},
	&"uw_shelf": {"fp": Vector2i(2, 1), "tall": true},
	&"uw_workbench": {"fp": Vector2i(2, 1), "tall": true},
	&"uw_sample_rack": {"fp": Vector2i(2, 1)},
	&"uw_crates": {"fp": Vector2i(1, 1), "nudge": Vector2(8, 0)},
	&"uw_bench": {"fp": Vector2i(2, 1)},
	&"uw_machine": {"fp": Vector2i(2, 1), "tall": true},
}

const ART_DECK := ["kit_wall_porthole", "kit_wall_gauge", "kit_wall_board", "kit_wall_porthole"]
const ART_LAB := ["kit_wall_screen", "kit_wall_chart", "kit_wall_porthole", "kit_wall_board"]
const ART_ENGINE := ["kit_wall_valves", "kit_wall_gauge", "kit_wall_valves"]

const _ENGINE_STEPS := [
	{"op": "along", "kind": &"uw_machine", "side": "n", "where": "spread", "n": [1, 3], "every": 2, "tag": "machine"},
	{"op": "along", "kind": &"pump", "side": "ew", "where": "spread", "n": [1, 3], "every": 2, "tag": "pump"},
	{"op": "along", "kind": &"pipes", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
	{"op": "pillars", "n": 2, "min_room": [9, 7]},
	{"op": "island", "kind": &"generator", "n": [0, 1], "margin": 2, "min_room": [9, 7]},
	{"op": "corner", "kind": [&"valve_wheel", &"cable_spool", &"uw_crates"], "n": [2, 3]},
	{"op": "fill", "kinds": [&"cable_spool", &"uw_crates", &"valve_wheel"], "ratio": 0.17, "max": 4},
	{"op": "decal", "mode": "scatter", "piece": [&"decal_stain_0", &"decal_puddle_0", &"decal_cables", &"decal_uw_tools"], "n": 4, "jitter": 10.0},
	{"op": "art", "pieces": ART_ENGINE, "density": 0.4},
]

const TEMPLATES := {
	&"quarters": {
		"steps": [
			{"op": "along", "kind": &"uw_bunk", "side": "n", "where": "spread", "n": [2, 5], "every": 2, "tag": "bunk"},
			{"op": "along", "kind": &"uw_locker_bank", "side": "ew", "where": "spread", "n": [1, 2], "every": 2, "tag": "lockers"},
			{"op": "rows", "kind": &"uw_bunk", "axis": "x", "row_gap": 2, "gap": 1, "margin": [2, 3, 2, 2], "max": 6, "min_room": [9, 8], "tag": "bunk"},
			{"op": "island", "kind": &"uw_table", "n": [1, 2], "margin": 1, "spacing": 2, "tag": "table"},
			{"op": "corner", "kind": [&"lamp_post", &"uw_crates"], "n": [1, 2]},
			{"op": "fill", "kinds": [&"uw_crates", &"lamp_post", &"oxygen_rack"], "ratio": 0.18, "max": 4},
			{"op": "decal", "mode": "near", "of": "table", "piece": &"decal_uw_papers", "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "bunk", "rel": "sides", "kinds": [&"uw_locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "beside", "of": "lockers", "rel": "sides"}, {"mode": "corner"}],
	},
	&"cabin": {
		"steps": [
			{"op": "along", "kind": &"uw_bunk", "side": "n", "where": "end", "n": 1, "tag": "bunk"},
			{"op": "along", "kind": &"desk", "side": "ew", "where": "center", "n": 1, "tag": "desk"},
			{"op": "along", "kind": &"uw_shelf", "side": "s", "n": [0, 1]},
			{"op": "corner", "kind": [&"lamp_post"], "n": 1},
			{"op": "decal", "mode": "near", "of": "desk", "piece": &"decal_uw_papers", "n": 1, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_porthole", "kit_wall_chart"], "density": 0.45},
		],
		"loot": [{"mode": "beside", "of": "bunk", "rel": "foot", "kinds": [&"uw_locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"mess": {
		"steps": [
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "end", "n": [1, 2], "tag": "pantry"},
			{"op": "along", "kind": &"uw_workbench", "side": "n", "where": "opposite", "of": "pantry", "n": 1, "tag": "galley"},
			{"op": "rows", "kind": &"mess_table", "axis": "x", "row_gap": 1, "gap": 1, "margin": [1, 3, 1, 1], "max": 6, "tag": "table"},
			{"op": "along", "kind": &"uw_bench", "side": "ew", "n": [0, 2]},
			{"op": "corner", "kind": [&"lamp_post", &"uw_crates"], "n": 2},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_uw_papers", &"decal_puddle_1"], "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "pantry", "rel": "sides", "kinds": [&"uw_crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"infirmary": {
		"steps": [
			{"op": "along", "kind": &"med_bed", "side": "n", "where": "spread", "n": [2, 4], "every": 2, "tag": "bed"},
			{"op": "along", "kind": &"uw_sample_rack", "side": "ew", "n": [1, 2], "tag": "rack"},
			{"op": "booth", "w": 2, "h": 2, "fill": &"specimen_tank", "min_room": [9, 6]},
			{"op": "island", "kind": &"desk", "n": 1, "margin": 1, "where": "end"},
			{"op": "corner", "kind": [&"lamp_post"], "n": 1},
			{"op": "art", "pieces": ART_LAB, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"uw_lab_cabinet"]}, {"mode": "in", "of": "booth"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"storage": {
		"steps": [
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "shelf"},
			{"op": "along", "kind": &"oxygen_rack", "side": "ew", "where": "spread", "n": [1, 3], "every": 2},
			{"op": "rows", "kind": &"uw_shelf", "axis": "x", "row_gap": 2, "gap": 1, "margin": [2, 3, 2, 2], "max": 4, "min_room": [8, 7]},
			{"op": "corner", "kind": [&"uw_crates", &"cable_spool", &"crate_stack"], "n": [2, 3]},
			{"op": "fill", "kinds": [&"uw_crates", &"crate_stack", &"cable_spool"], "ratio": 0.22, "max": 5},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_stain_1", &"decal_uw_tools"], "n": 2, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_board", "kit_wall_gauge"], "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides", "kinds": [&"uw_crate", &"uw_tank"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"comms": {
		"steps": [
			{"op": "along", "kind": &"console", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "console"},
			{"op": "along", "kind": &"server_rack", "side": "ew", "where": "spread", "n": [1, 3], "every": 1},
			{"op": "island", "kind": &"uw_table", "n": 1, "margin": 2, "tag": "table"},
			{"op": "decal", "mode": "under", "of": "table", "piece": &"decal_uw_mat", "shift": Vector2(0, 30)},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_cables"], "n": 2, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_screen", "kit_wall_chart", "kit_wall_screen"], "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "console", "rel": "sides", "kinds": [&"uw_locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"workshop": {
		"steps": [
			{"op": "along", "kind": &"uw_workbench", "side": "n", "where": "spread", "n": [1, 3], "every": 2, "tag": "bench"},
			{"op": "along", "kind": &"diving_suit", "side": "ew", "where": "spread", "n": [1, 3], "every": 1},
			{"op": "island", "kind": &"uw_workbench", "n": [0, 1], "margin": 2, "min_room": [8, 7]},
			{"op": "corner", "kind": [&"cable_spool", &"uw_crates"], "n": [1, 2]},
			{"op": "fill", "kinds": [&"cable_spool", &"uw_crates", &"oxygen_rack"], "ratio": 0.17, "max": 4},
			{"op": "decal", "mode": "near", "of": "bench", "piece": [&"decal_uw_tools", &"decal_stain_0"], "n": 2, "jitter": 12.0},
			{"op": "art", "pieces": ART_ENGINE, "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "bench", "rel": "sides", "kinds": [&"uw_crate", &"uw_tank"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"moon_pool": {
		"steps": [
			{"op": "along", "kind": &"diving_suit", "side": "n", "where": "spread", "n": [1, 3], "every": 1},
			{"op": "along", "kind": &"oxygen_rack", "side": "ew", "n": [1, 2]},
			{"op": "corner", "kind": [&"cable_spool", &"lamp_post"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_gauge", "kit_wall_valves"], "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"pod_bay": {
		"steps": [
			{"op": "along", "kind": &"console", "side": "n", "where": "center", "n": 1, "tag": "console"},
			{"op": "along", "kind": &"oxygen_rack", "side": "ew", "where": "spread", "n": [1, 2], "every": 2},
			{"op": "along", "kind": &"uw_bench", "side": "s", "n": [1, 2]},
			{"op": "corner", "kind": [&"alarm_light", &"lamp_post", &"uw_crates"], "n": 2},
			{"op": "art", "pieces": ART_DECK, "density": 0.35},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"aquarium": {
		"steps": [
			{"op": "along", "kind": &"aquarium_tank", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "tank"},
			{"op": "along", "kind": &"aquarium_tank", "side": "ew", "where": "spread", "n": [1, 3], "every": 1, "tag": "tank"},
			{"op": "island", "kind": &"uw_bench", "n": [1, 2], "margin": 2, "spacing": 2},
			{"op": "corner", "kind": [&"coral_cluster", &"kelp"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_porthole", "kit_wall_chart"], "density": 0.35},
		],
		"loot": [{"mode": "corner"}],
	},
	&"bio_lab": {
		"steps": [
			{"op": "along", "kind": &"uw_sample_rack", "side": "n", "where": "spread", "n": [1, 3], "every": 1, "tag": "rack"},
			{"op": "along", "kind": &"specimen_tank", "side": "ew", "where": "spread", "n": [1, 3], "every": 1, "tag": "tank"},
			{"op": "rows", "kind": &"lab_bench", "axis": "x", "row_gap": 1, "gap": 1, "margin": [2, 3, 2, 1], "max": 6, "tag": "bench"},
			{"op": "booth", "w": 2, "h": 2, "fill": &"server_rack", "min_room": [10, 7]},
			{"op": "fill", "kinds": [&"specimen_tank", &"uw_crates"], "ratio": 0.18, "max": 3},
			{"op": "decal", "mode": "near", "of": "bench", "piece": [&"decal_uw_papers", &"decal_algae_0"], "n": 1, "jitter": 12.0},
			{"op": "art", "pieces": ART_LAB, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"uw_lab_cabinet"]}, {"mode": "in", "of": "booth"}, {"mode": "corner"}],
		"hide": [{"mode": "beside", "of": "bench", "rel": "sides"}, {"mode": "corner"}],
	},
	&"dissection": {
		"steps": [
			{"op": "island", "kind": &"med_bed", "n": [1, 2], "margin": 2, "spacing": 2, "tag": "table"},
			{"op": "along", "kind": &"specimen_tank", "side": "n", "where": "spread", "n": [2, 4], "every": 1},
			{"op": "along", "kind": &"uw_sample_rack", "side": "ew", "n": [1, 2], "tag": "rack"},
			{"op": "corner", "kind": [&"lamp_post", &"uw_crates"], "n": 2},
			{"op": "decal", "mode": "near", "of": "table", "piece": [&"decal_stain_0", &"decal_puddle_2"], "n": 2, "jitter": 12.0},
			{"op": "art", "pieces": ART_LAB, "density": 0.35},
		],
		"loot": [{"mode": "beside", "of": "rack", "rel": "sides", "kinds": [&"uw_lab_cabinet"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"hydroponics": {
		"steps": [
			{"op": "rows", "kind": &"hydro_planter", "axis": "x", "row_gap": 1, "gap": 0, "margin": [1, 1, 1, 1], "max": 12},
			{"op": "along", "kind": &"pipes", "side": "n", "n": [0, 1]},
			{"op": "corner", "kind": [&"lamp_post"], "n": 1},
			{"op": "art", "pieces": ["kit_wall_valves", "kit_wall_gauge"], "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"server": {
		"steps": [
			{"op": "along", "kind": &"server_rack", "side": "n", "where": "spread", "n": [3, 6], "every": 1},
			{"op": "rows", "kind": &"server_rack", "axis": "x", "row_gap": 2, "gap": 0, "margin": [1, 3, 1, 2], "max": 8},
			{"op": "along", "kind": &"console", "side": "ew", "n": 1, "tag": "console"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_cables"], "n": 3, "jitter": 8.0},
			{"op": "art", "pieces": ["kit_wall_screen", "kit_wall_gauge"], "density": 0.3},
		],
		"loot": [{"mode": "corner"}],
	},
	&"office": {
		"steps": [
			{"op": "along", "kind": &"desk", "side": "n", "where": "spread", "n": [1, 3], "every": 2, "tag": "desk"},
			{"op": "along", "kind": &"aquarium_tank", "side": "ew", "n": [1, 2]},
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "ends", "n": [0, 1]},
			{"op": "island", "kind": &"uw_table", "n": [1, 2], "margin": 2, "spacing": 2, "tag": "table"},
			{"op": "corner", "kind": [&"lamp_post", &"kelp"], "n": 2},
			{"op": "decal", "mode": "under", "of": "table", "piece": &"decal_uw_mat", "shift": Vector2(0, 30)},
			{"op": "art", "pieces": ART_LAB, "density": 0.4},
		],
		"loot": [{"mode": "beside", "of": "desk", "rel": "sides", "kinds": [&"uw_locker", &"uw_lab_cabinet"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"lab_storage": {
		"steps": [
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "spread", "n": [2, 4], "every": 1, "tag": "shelf"},
			{"op": "along", "kind": &"uw_sample_rack", "side": "ew", "n": [1, 2]},
			{"op": "rows", "kind": &"uw_shelf", "axis": "x", "row_gap": 2, "gap": 1, "margin": [2, 3, 2, 2], "max": 4},
			{"op": "corner", "kind": [&"uw_crates", &"crate_stack"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_board", "kit_wall_chart"], "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides", "kinds": [&"uw_lab_cabinet", &"uw_crate"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"decon": {
		"steps": [
			{"op": "stalls", "side": "n", "len": 2, "spacing": 2, "n": [2, 3], "min_room": [8, 5]},
			{"op": "along", "kind": &"diving_suit", "side": "n", "where": "spread", "n": [2, 3], "every": 2},
			{"op": "along", "kind": &"uw_bench", "side": "s", "n": [1, 2]},
			{"op": "along", "kind": &"uw_locker_bank", "side": "ew", "n": [1, 2], "tag": "lockers"},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_puddle_0", &"decal_puddle_1", &"decal_drain"], "n": 3, "jitter": 10.0},
			{"op": "art", "pieces": ["kit_wall_valves", "kit_wall_gauge"], "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "lockers", "rel": "sides", "kinds": [&"uw_locker"]}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"pump_room": {"steps": _ENGINE_STEPS, "loot": [{"mode": "beside", "of": "pump", "rel": "sides", "kinds": [&"uw_tank"]}, {"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"engine": {"steps": _ENGINE_STEPS, "loot": [{"mode": "beside", "of": "machine", "rel": "sides", "kinds": [&"uw_tank"]}, {"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"ballast": {"steps": _ENGINE_STEPS, "loot": [{"mode": "corner"}], "hide": [{"mode": "corner"}]},
	&"maintenance": {
		"steps": [
			{"op": "along", "kind": &"uw_workbench", "side": "n", "where": "end", "n": 1, "tag": "bench"},
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "opposite", "of": "bench", "n": 1, "tag": "shelf"},
			{"op": "along", "kind": &"diving_suit", "side": "ew", "n": [1, 2]},
			{"op": "island", "kind": &"uw_machine", "n": [0, 1], "margin": 2, "min_room": [8, 7]},
			{"op": "corner", "kind": [&"cable_spool", &"uw_crates", &"lamp_post"], "n": [2, 3]},
			{"op": "fill", "kinds": [&"uw_crates", &"cable_spool"], "ratio": 0.16, "max": 3},
			{"op": "decal", "mode": "near", "of": "bench", "piece": [&"decal_uw_tools"], "n": 2, "jitter": 12.0},
			{"op": "art", "pieces": ART_ENGINE, "density": 0.3},
		],
		"loot": [{"mode": "beside", "of": "shelf", "rel": "sides"}, {"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
	&"escape_pod": {
		"steps": [
			{"op": "along", "kind": &"oxygen_rack", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
			{"op": "along", "kind": &"uw_bench", "side": "ew", "n": [1, 2]},
			{"op": "corner", "kind": [&"alarm_light", &"uw_crates"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_gauge", "kit_wall_porthole"], "density": 0.35},
		],
		"loot": [{"mode": "corner"}],
	},
	&"sample_vault": {
		"steps": [
			{"op": "along", "kind": &"uw_sample_rack", "side": "n", "where": "spread", "n": [1, 2], "every": 1},
			{"op": "corner", "kind": [&"specimen_tank"], "n": [1, 2]},
			{"op": "art", "pieces": ["kit_wall_screen"], "density": 0.35},
		],
		"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
	},
	&"trench_vault": {
		"steps": [
			{"op": "corner", "kind": [&"coral_cluster", &"uw_crates"], "n": 2},
			{"op": "art", "pieces": ["kit_wall_gauge"], "density": 0.3},
		],
		"loot": [{"mode": "along", "side": "n"}, {"mode": "corner"}],
	},
	&"flooded_hall": {
		"steps": [
			{"op": "pillars", "n": 4, "min_room": [9, 7]},
			{"op": "along", "kind": &"uw_shelf", "side": "n", "where": "spread", "n": [1, 2], "every": 2},
			{"op": "corner", "kind": [&"coral_cluster", &"kelp", &"uw_crates"], "n": [2, 3]},
			{"op": "fill", "kinds": [&"coral_cluster", &"kelp", &"uw_crates"], "ratio": 0.15, "max": 4},
			{"op": "decal", "mode": "scatter", "piece": [&"decal_algae_0", &"decal_algae_1", &"decal_silt"], "n": 5, "jitter": 14.0},
			{"op": "art", "pieces": ["kit_wall_porthole", "kit_wall_valves"], "density": 0.25},
		],
		"loot": [{"mode": "corner"}],
		"hide": [{"mode": "corner"}],
	},
}
