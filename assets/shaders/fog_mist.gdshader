shader_type canvas_item;
// Brouillard, option B « brume stylisée » ([fog] fog_style="mist").
// Un seul rectangle en espace monde (z 80), une passe, sans boucle, 4 lectures de texture
// (celles de fog_common). Brume moins opaque et plus lumineuse dans la palette de la DA
// (bleu nuit vers violet, accent violet électrique très discret), dégradé progressif depuis
// le bord de vision (canal G du masque), grain fin, jamais de noir pur. Ennemis et
// conteneurs hors vue sont cachés par FogOfWar (groupe fog_hideable), pas par ce shader.

#include "res://assets/shaders/fog_common.gdshaderinc"

// Brume profonde (loin du bord), brume claire (près du bord), accent violet (#7C4DFF).
uniform vec4 deep_color : source_color = vec4(0.09, 0.1, 0.22, 1.0);
uniform vec4 light_color : source_color = vec4(0.23, 0.24, 0.46, 1.0);
uniform vec4 accent_color : source_color = vec4(0.486, 0.302, 1.0, 1.0);
uniform float accent_strength : hint_range(0.0, 1.0) = 0.12;
// Opacité : zone jamais vue, zone explorée, et baisse d'opacité au plus près du bord.
uniform float unseen_alpha : hint_range(0.0, 1.0) = 0.95;
uniform float explored_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float halo_alpha_drop : hint_range(0.0, 0.5) = 0.06;
// Volutes (éclaircissement des crêtes) et grain fin (amplitude, images/s).
uniform float mist_density : hint_range(0.0, 1.0) = 0.5;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.035;
uniform float grain_fps = 24.0;
uniform float visible_haze : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	FogSample s = fog_sample(world_pos, TIME);
	// Dégradé depuis le bord de vision : clair et violet près du bord, profond au loin.
	float g = smoothstep(0.0, 1.0, s.halo);
	vec3 col = mix(deep_color.rgb, light_color.rgb, g * 0.85 + s.wisp * mist_density * 0.35);
	col += light_color.rgb * smoothstep(0.55, 0.8, s.n1 * 0.6 + s.n2 * 0.5) * mist_density * 0.25;
	col = mix(col, accent_color.rgb, accent_strength * (g * 0.7 + s.wisp * 0.3));
	// Grain fin, animé (par pixel écran) : texture de brume, sans motif visible.
	float grain = fog_hash(floor(FRAGCOORD.xy) + floor(TIME * grain_fps) * vec2(17.0, 31.0)) - 0.5;
	col += grain * grain_strength;
	col = max(col, deep_color.rgb * 0.8);  // jamais de noir pur

	float base_a = mix(unseen_alpha, explored_alpha, s.memory);
	float fog_a = clamp(base_a - g * halo_alpha_drop - s.wisp * mist_density * 0.03, 0.0, 1.0);
	float haze = visible_haze * s.wisp * smoothstep(0.2, 0.95, s.dist) * (1.0 - reveal);
	float a = fog_a * (1.0 - s.vis) + haze * s.vis;
	COLOR = vec4(col, a);
}
