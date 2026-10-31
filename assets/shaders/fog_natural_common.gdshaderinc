// Brouillard « naturel » sans lecture de l'écran (perf/brouillard-sans-copie).
// L'ancienne version lisait l'image déjà dessinée (hint_screen_texture) : copie de tout l'écran à
// chaque image, à la résolution native, très coûteuse sur les GPU mobiles (vidage des tuiles).
// Le même calcul est réécrit sous la forme  image = décor × F + B  et rendu en DEUX passes posées
// par-dessus le décor, sans copie :
//   fog_natural.gdshader      (blend_mul)          : décor × F
//   fog_natural_add.gdshader  (blend_premul_alpha) : + B
// Seule la désaturation hors vue ne peut pas s'écrire ainsi (elle mélange les canaux) : la
// luminance du décor y est approchée par une part du décor lui-même (desat_keep) plus un gris
// constant (desat_luminance). Réglages : [fog_natural] de data/balance.cfg.

#include "res://assets/shaders/fog_common.gdshaderinc"

uniform vec4 shade_tint : source_color = vec4(0.7, 0.76, 1.0, 1.0);
uniform vec4 shade_floor : source_color = vec4(0.03, 0.035, 0.06, 1.0);
uniform float explored_brightness : hint_range(0.0, 1.0) = 0.5;
uniform float explored_saturation : hint_range(0.0, 1.0) = 0.42;
uniform float unseen_brightness : hint_range(0.0, 1.0) = 0.14;
uniform float unseen_saturation : hint_range(0.0, 1.0) = 0.15;
uniform float penumbra_light : hint_range(0.0, 1.0) = 0.55;
uniform float penumbra_curve : hint_range(0.3, 4.0) = 1.6;
uniform vec4 mist_color : source_color = vec4(0.2, 0.24, 0.38, 1.0);
uniform float mist_density : hint_range(0.0, 1.0) = 0.16;
uniform vec4 dusk_color : source_color = vec4(1.0, 0.86, 0.72, 1.0);
uniform float dusk_strength : hint_range(0.0, 1.0) = 0.18;
// Approximation de la désaturation : part de la luminance rendue par le décor lui-même (couleur
// gardée) et gris constant pour le reste (luminance moyenne du décor).
uniform float desat_keep : hint_range(0.0, 1.0) = 0.6;
uniform float desat_luminance : hint_range(0.0, 1.0) = 0.3;

// F (facteur du décor) et B (ajout), pour  image = décor × F + B.
void natural_terms(vec2 wp, float time, out vec3 f, out vec3 b) {
	FogSample s = fog_sample(wp, time);
	float sat = mix(unseen_saturation, explored_saturation, s.memory);
	float bright = mix(unseen_brightness, explored_brightness, s.memory);
	float mist = s.wisp * mist_density * (0.6 + 0.4 * smoothstep(0.4, 1.2, s.dist));
	float pen = pow(clamp(s.halo, 0.0, 1.0), penumbra_curve) * penumbra_light;
	float light = max(s.vis, pen);
	float dark = 1.0 - light;
	vec3 dusk = mix(vec3(1.0), dusk_color.rgb, dusk_strength * smoothstep(0.35, 1.0, s.dist));
	// Hors vue : plancher + mix(lum, décor, sat) × teinte × luminosité, puis brume.
	// lum ≈ desat_keep × décor + (1 - desat_keep) × desat_luminance.
	float scene_k = sat + (1.0 - sat) * desat_keep;
	vec3 grey = vec3((1.0 - sat) * (1.0 - desat_keep) * desat_luminance);
	vec3 mc = mist_color.rgb * (0.75 + 0.4 * s.n1);
	f = light * dusk + dark * (1.0 - mist) * scene_k * shade_tint.rgb * bright;
	b = dark * ((1.0 - mist) * (shade_floor.rgb + grey * shade_tint.rgb * bright) + mist * mc);
}
