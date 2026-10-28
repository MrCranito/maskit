## Généré par art/blender/mall/build_mall_enemies.py : NE PAS ÉDITER.
## Visuels des ennemis du centre commercial (format EnemyVisual.KINDS), chargés par BiomeRegistry.
## Sprites rendus sous Blender (2 px par unité monde) : scale = 0.5.

const KINDS := {
	&"mall_guard": {
		"path": "res://assets/sprites/mall/enemies/mall_guard.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(128.0, 173.8), "scale": 0.5,
		"head": Vector2(0, -62.3), "shadow": 20.0,
		"eyes": [Vector2(128.6, 100.5), Vector2(142.8, 97.0)], "eye_r": 3.6,
		"aura": Color(0.35, 0.95, 1.00),
		"debris": [Color(0.180, 0.227, 0.369), Color(0.949, 0.925, 0.886), Color(0.910, 0.690, 0.251)],
	},
	&"mall_clown": {
		"path": "res://assets/sprites/mall/enemies/mall_clown.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(128.0, 171.4), "scale": 0.5,
		"head": Vector2(0, -59.2), "shadow": 18.0,
		"eyes": [Vector2(128.5, 102.1), Vector2(142.0, 98.8)], "eye_r": 3.6,
		"aura": Color(1.00, 0.30, 0.30),
		"debris": [Color(0.416, 0.227, 0.588), Color(0.949, 0.925, 0.886), Color(0.910, 0.471, 0.180), Color(0.290, 0.627, 0.314)],
	},
	&"mall_sniper": {
		"path": "res://assets/sprites/mall/enemies/mall_sniper.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(128.0, 173.8), "scale": 0.5,
		"head": Vector2(0, -61.3), "shadow": 18.0,
		"eyes": [Vector2(128.6, 101.8), Vector2(142.5, 98.4)], "eye_r": 3.6,
		"aura": Color(0.40, 0.95, 1.00),
		"debris": [Color(0.290, 0.188, 0.376), Color(0.416, 0.416, 0.471), Color(0.227, 0.604, 0.604)],
	},
	&"mall_mannequin": {
		"path": "res://assets/sprites/mall/enemies/mall_mannequin.png",
		"svg_size": Vector2(256, 256), "feet": Vector2(128.0, 176.2), "scale": 0.5,
		"head": Vector2(0, -62.3), "shadow": 19.0,
		"eyes": [Vector2(128.6, 102.5), Vector2(142.5, 99.2)], "eye_r": 3.6,
		"aura": Color(0.75, 0.42, 1.00),
		"debris": [Color(0.925, 0.894, 0.863), Color(0.416, 0.227, 0.588), Color(0.753, 0.149, 0.180), Color(0.910, 0.690, 0.251)],
	},
	&"mall_director": {
		"path": "res://assets/sprites/mall/enemies/mall_director.png",
		"svg_size": Vector2(512, 512), "feet": Vector2(256.0, 335.5), "scale": 0.5,
		"head": Vector2(0, -85.2), "shadow": 44.0,
		"eyes": [Vector2(256.8, 221.2), Vector2(272.7, 217.3)], "eye_r": 5.0,
		"aura": Color(1.00, 0.60, 0.20),
		"debris": [Color(0.227, 0.227, 0.275), Color(0.910, 0.690, 0.251), Color(0.753, 0.149, 0.180), Color(0.910, 0.894, 0.933)],
	},
}
