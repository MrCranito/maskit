shader_type canvas_item;
// Sol peint tuilable (module Décor) : UV en coordonnées monde (nœud à l'origine),
// léger gauchissement + mélange d'une 2e texture et variation de valeur à grande
// échelle (texture « macro ») pour casser la répétition. 2 à 3 lectures de texture, pas de boucle.

uniform sampler2D tex_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_b : repeat_enable, filter_linear_mipmap;
uniform sampler2D macro : repeat_enable, filter_linear;
uniform float tile_world = 256.0;
uniform float b_amount = 0.0;
uniform float value_var = 0.12;
uniform float warp = 0.05;

varying vec2 world;
varying vec4 vcol;

void vertex() {
	world = VERTEX;
	vcol = COLOR;
}

void fragment() {
	vec4 m = texture(macro, world / 2304.0);
	vec2 uv = world / tile_world + (m.rg - 0.5) * warp;
	vec3 c = texture(tex_a, uv).rgb;
	// 2e texture seulement pour les sols qui la mélangent (branche sur uniforme : cohérente,
	// pas de coût de divergence) → 2 lectures au lieu de 3 pour planchers et mine.
	if (b_amount > 0.0) {
		vec3 b = texture(tex_b, uv * 0.91 + vec2(0.37, 0.61)).rgb;
		c = mix(c, b, smoothstep(0.48, 0.66, m.b) * b_amount);
	}
	c *= 1.0 + (m.g - 0.5) * 2.0 * value_var;
	COLOR = vec4(c, 1.0) * vcol;
}
