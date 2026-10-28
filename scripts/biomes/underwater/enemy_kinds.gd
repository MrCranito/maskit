extends RefCounted
## Visuels des ennemis de la station sous-marine (format EnemyVisual.KINDS), chargés par
## BiomeRegistry. Généré par art/blender/underwater/uw_enemies.py : NE PAS ÉDITER à la main.
## Sprites PNG rendus sous Blender : svg_size = taille du PNG, scale = unités monde par px.

const KINDS: Dictionary = {
	&"uw_diver": {
		"path": "res://assets/sprites/underwater/enemies/uw_diver.png",
		"svg_size": Vector2(128, 128), "feet": Vector2(38.1, 112.0), "scale": 0.5406,
		"head": Vector2(0, -66.0), "shadow": 17.0,
		"eyes": [Vector2(53.0, 36.5), Vector2(40.0, 40.4)], "eye_r": 2.3,
		"aura": Color(0.3, 0.92, 1.0),
		"debris": [Color(0.145, 0.204, 0.243), Color(0.937, 0.91, 0.863), Color(0.878, 0.471, 0.18)],
	},
	&"uw_mutant": {
		"path": "res://assets/sprites/underwater/enemies/uw_mutant.png",
		"svg_size": Vector2(128, 128), "feet": Vector2(49.5, 101.5), "scale": 0.5705,
		"head": Vector2(0, -64.0), "shadow": 18.0,
		"eyes": [Vector2(63.0, 32.8), Vector2(52.5, 35.9)], "eye_r": 2.3,
		"aura": Color(0.55, 1.0, 0.35),
		"debris": [Color(0.839, 0.863, 0.824), Color(0.541, 0.353, 0.627), Color(0.941, 0.784, 0.69)],
	},
	&"uw_heavy": {
		"path": "res://assets/sprites/underwater/enemies/uw_heavy.png",
		"svg_size": Vector2(128, 128), "feet": Vector2(51.2, 110.3), "scale": 0.6381,
		"head": Vector2(0, -76.0), "shadow": 28.0,
		"eyes": [Vector2(68.2, 44.6), Vector2(57.2, 47.9)], "eye_r": 2.3,
		"aura": Color(1.0, 0.6, 0.18),
		"debris": [Color(0.784, 0.604, 0.251), Color(0.353, 0.4, 0.439), Color(0.29, 0.306, 0.345)],
	},
	&"uw_eel": {
		"path": "res://assets/sprites/underwater/enemies/uw_eel.png",
		"svg_size": Vector2(128, 128), "feet": Vector2(71.8, 116.8), "scale": 0.4314,
		"head": Vector2(0, -56.0), "shadow": 22.0,
		"eyes": [Vector2(105.0, 57.4), Vector2(91.7, 61.3)], "eye_r": 2.3,
		"aura": Color(1.0, 0.25, 0.2),
		"debris": [Color(0.18, 0.353, 0.353), Color(0.925, 0.886, 0.8), Color(0.353, 1.0, 0.878)],
	},
	&"uw_guardian": {
		"path": "res://assets/sprites/underwater/enemies/uw_guardian.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(120.7, 212.1), "scale": 0.5575,
		"head": Vector2(0, -124.0), "shadow": 48.0,
		"eyes": [Vector2(149.9, 94.3), Vector2(122.6, 102.5)], "eye_r": 3.6,
		"aura": Color(0.35, 0.95, 1.0),
		"debris": [Color(0.541, 0.478, 0.471), Color(0.91, 0.408, 0.431), Color(0.941, 0.565, 0.282), Color(0.925, 0.886, 0.8)],
	},
}
