shader_type canvas_item;
// Tranche d'occultation du fond pré-rendu (PrerenderBackdrop) : ne garde, dans la région de la
// tuile du fond, que les pixels dont l'id (texture o_*.png, R = rangée + 1, G = bâtiment + 1)
// correspond au code de la tranche, passé par la couleur de modulation (r, g) ; b = opacité
// (bâtiment dont le toit s'efface). Même matériau pour toutes les tranches d'une tuile.
// Le joueur masqué par une tranche (tranche plus au sud que ses pieds) reste lisible : les
// pixels autour de sa silhouette passent à `player_alpha`.
uniform sampler2D id_tex : filter_nearest, repeat_disable;
uniform vec2 player_feet = vec2(-100000.0);
uniform float player_alpha = 0.6;
varying vec4 code;
varying vec2 wpos;

void vertex() {
	code = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 id = texture(id_tex, UV);
	if (abs(id.r - code.r) > 0.0019 || abs(id.g - code.g) > 0.0019) {
		discard;
	}
	vec4 c = texture(TEXTURE, UV);
	float a = c.a * code.b;
	float sort_y = floor(code.r * 255.0 + 0.5) * 64.0;
	if (sort_y > player_feet.y) {
		vec2 d = (wpos - (player_feet + vec2(0.0, -42.0))) / vec2(40.0, 64.0);
		a *= mix(player_alpha, 1.0, smoothstep(0.75, 1.0, dot(d, d)));
	}
	COLOR = vec4(c.rgb, a);
}
