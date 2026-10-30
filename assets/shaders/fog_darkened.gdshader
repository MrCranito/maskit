shader_type canvas_item;
// Brouillard, option A « décor assombri » ([fog] fog_style="darkened").
// Un seul rectangle en espace monde (z 80), une passe, sans boucle, 5 lectures de texture :
// les 4 de fog_common + l'écran déjà dessiné (décor sous le brouillard).
// Hors du champ de vision, le décor reste lisible mais désaturé, assombri et teinté bleu
// nuit (zones explorées) ; une zone jamais vue est presque noire-bleutée (quasi illisible).
// Bord de vision net mais doux, brume légère animée par-dessus. Ennemis et conteneurs hors
// vue sont cachés par FogOfWar (groupe fog_hideable), pas par ce shader.

#include "res://assets/shaders/fog_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// Teinte multiplicative du décor hors vue (bleu nuit) et plancher (jamais de noir pur).
uniform vec4 shade_tint : source_color = vec4(0.55, 0.66, 1.0, 1.0);
uniform vec4 shade_floor : source_color = vec4(0.025, 0.035, 0.075, 1.0);
// Zones explorées hors vue : luminosité et saturation restantes du décor.
uniform float explored_brightness : hint_range(0.0, 1.0) = 0.42;
uniform float explored_saturation : hint_range(0.0, 1.0) = 0.3;
// Zones jamais vues : luminosité et saturation restantes (quasi illisible).
uniform float unseen_brightness : hint_range(0.0, 1.0) = 0.06;
uniform float unseen_saturation : hint_range(0.0, 1.0) = 0.0;
// Brume légère par-dessus le décor assombri.
uniform vec4 mist_color : source_color = vec4(0.22, 0.27, 0.48, 1.0);
uniform float mist_density : hint_range(0.0, 1.0) = 0.22;
// Liseré du bord de vision (pénombre bleu nuit) et brume résiduelle dans la zone visible.
uniform vec4 penumbra_color : source_color = vec4(0.1, 0.13, 0.3, 1.0);
uniform float penumbra_strength : hint_range(0.0, 1.0) = 0.35;
uniform float visible_haze : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	FogSample s = fog_sample(world_pos, TIME);
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;

	// Décor hors vue : désaturé, assombri, teinté bleu nuit.
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	float sat = mix(unseen_saturation, explored_saturation, s.memory);
	float bright = mix(unseen_brightness, explored_brightness, s.memory);
	vec3 dark = shade_floor.rgb + mix(vec3(lum), scene, sat) * shade_tint.rgb * bright;
	// Brume animée, plus présente sur l'inconnu que sur le connu.
	float mist = s.wisp * mist_density * (1.0 - 0.4 * s.memory);
	dark = mix(dark, mist_color.rgb * (0.7 + 0.5 * s.n1), mist);

	// Pénombre au bord du champ de vision (fine bande bleu nuit, pas de mur noir).
	float pen = s.vis * (1.0 - s.vis) * 4.0;
	vec3 col = mix(dark, scene, s.vis);
	col = mix(col, penumbra_color.rgb, pen * penumbra_strength * (1.0 - reveal));
	// Brume résiduelle très légère dans la zone visible, croissante vers le bord.
	float haze = visible_haze * s.wisp * smoothstep(0.2, 0.95, s.dist) * s.vis * (1.0 - reveal);
	col = mix(col, mist_color.rgb, haze);
	COLOR = vec4(col, 1.0);
}
