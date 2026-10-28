extends RefCounted
## Visuels des ennemis de la Station Orbitale Kagami (format EnemyVisual.KINDS), chargés par
## BiomeRegistry. Généré par art/blender/space_station/build_enemies.py : NE PAS ÉDITER.
## PNG en vue 3/4 de face ; scale = 0,5 unité monde par px ; pieds/yeux en px du PNG.

const DIR := "res://assets/sprites/space_station/enemies/"

const KINDS := {
	# Drone de sécurité masqué
	&"space_drone": {
		"path": DIR + "space_drone.png",
		"svg_size": Vector2(128, 128), "feet": Vector2(64.0, 125.4), "scale": 0.5,
		"head": Vector2(0, -55), "shadow": 20.8,
		"eyes": [Vector2(42.6, 80.6), Vector2(58.3, 85.3)], "eye_r": 4.0,
		"aura": Color(1.00, 0.23, 0.16),
		"debris": [Color(0.91, 0.89, 0.86), Color(0.23, 0.24, 0.31), Color(1.00, 0.19, 0.13)],
	},
	# Soldat au masque de spectre
	&"space_soldier": {
		"path": DIR + "space_soldier.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(127.5, 234.3), "scale": 0.5,
		"head": Vector2(0, -74), "shadow": 28.1,
		"eyes": [Vector2(107.8, 138.8), Vector2(122.6, 143.2)], "eye_r": 3.6,
		"aura": Color(0.38, 0.94, 1.00),
		"debris": [Color(0.18, 0.23, 0.37), Color(0.78, 0.82, 0.86), Color(0.27, 0.77, 0.94)],
	},
	# Androïde marionnette
	&"space_android": {
		"path": DIR + "space_android.png",
		"svg_size": Vector2(128, 256), "feet": Vector2(63.5, 234.1), "scale": 0.5,
		"head": Vector2(0, -72), "shadow": 25.2,
		"eyes": [Vector2(48.2, 131.3), Vector2(62.1, 135.4)], "eye_r": 3.4,
		"aura": Color(0.75, 0.44, 1.00),
		"debris": [Color(0.77, 0.80, 0.85), Color(0.89, 0.85, 0.77), Color(0.75, 0.44, 1.00)],
	},
	# Brute en exosquelette
	&"space_brute": {
		"path": DIR + "space_brute.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(128.0, 223.1), "scale": 0.5,
		"head": Vector2(0, -93), "shadow": 55.5,
		"eyes": [Vector2(104.2, 91.0), Vector2(124.0, 96.8)], "eye_r": 4.2,
		"aura": Color(1.00, 0.69, 0.25),
		"debris": [Color(0.85, 0.45, 0.17), Color(0.16, 0.16, 0.20), Color(0.85, 0.65, 0.25)],
	},
	# Colosse du réacteur (boss)
	&"space_reactor_colossus": {
		"path": DIR + "space_reactor_colossus.png",
		"svg_size": Vector2(512, 512), "feet": Vector2(255.5, 471.2), "scale": 0.5,
		"head": Vector2(0, -135), "shadow": 85.1,
		"eyes": [Vector2(226.5, 289.9), Vector2(248.8, 296.5)], "eye_r": 5.4,
		"aura": Color(0.38, 0.94, 1.00),
		"debris": [Color(0.29, 0.31, 0.39), Color(0.48, 0.94, 1.00), Color(0.78, 0.63, 0.25), Color(0.35, 0.38, 0.47)],
	},
}
