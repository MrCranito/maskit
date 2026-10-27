shader_type canvas_item;
// Brouillard de guerre (FogOfWar). TEXTURE = masque RG8, 1 texel par case :
//   R = visible (0..1), G = explorée (0..1) ; valeurs interpolées pendant les transitions.
// Deux canaux séparés : le filtre linéaire entre une case visible et une case jamais
// vue ne fabrique pas de faux liseré « exploré ».
// Le Sprite2D est mis à l'échelle TILE_SIZE et filtré en linéaire ; le smoothstep
// transforme le dégradé de case à case en bord doux, sans effet « cases ».
// Pas de lecture d'écran (coût mobile) : la zone explorée est voilée par une teinte
// bleu nuit, ce qui l'assombrit et la désature tout en gardant le décor lisible.

uniform vec2 map_cells = vec2(40.0, 30.0);
uniform vec4 unseen_color : source_color = vec4(0.02, 0.03, 0.07, 0.97);
uniform vec4 explored_tint : source_color = vec4(0.05, 0.07, 0.14, 1.0);
uniform float explored_veil : hint_range(0.0, 1.0) = 0.6;
// Largeur du fondu (en valeur de masque) ; plus petit = bord plus net.
uniform float edge_softness : hint_range(0.05, 1.0) = 0.5;
// Seuil du bord (< 0.5 : la zone claire déborde un peu sur les cases voisines,
// ce qui laisse voir entièrement la face des murs en bord de vue).
uniform float edge_center : hint_range(0.1, 0.9) = 0.4;
uniform float mist_strength : hint_range(0.0, 0.5) = 0.12;
uniform float mist_speed = 0.15;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 m = texture(TEXTURE, UV).rg;
	// Brume douce : bruit animé, appliqué seulement là où le masque est intermédiaire.
	vec2 cell = UV * map_cells;
	float t = TIME * mist_speed;
	float n = vnoise(cell * 0.9 + vec2(t, -t * 0.7)) * 0.65
		+ vnoise(cell * 2.3 - vec2(t * 1.3, t)) * 0.35 - 0.5;
	vec2 edge = 1.0 - abs(m * 2.0 - 1.0);  // 1 au milieu d'un fondu, 0 aux paliers
	m += n * mist_strength * edge * 2.0;

	float h = edge_softness * 0.5;
	float vis = smoothstep(edge_center - h, edge_center + h, m.r);
	float expl = smoothstep(edge_center - h, edge_center + h, m.g);

	// Couleur/alpha du voile : jamais vu → exploré → visible.
	float alpha = mix(unseen_color.a, explored_veil, expl) * (1.0 - vis);
	vec3 col = mix(unseen_color.rgb, explored_tint.rgb, expl);
	COLOR = vec4(col, alpha);
}
