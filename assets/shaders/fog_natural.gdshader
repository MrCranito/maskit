shader_type canvas_item;
// Brouillard « naturel » ([fog] fog_style="natural") : comme le décor assombri (option A), le
// décor reste lisible hors vue, en version nuit désaturée ; mais rien n'est coupé net :
//   - bord du champ de vision large et irrégulier ([fog_natural] edge_feather_px, edge_softness) ;
//   - pénombre : au-delà du bord, la lumière décroît sur un large dégradé (halo du masque,
//     canal G, [fog_natural] halo_px) au lieu de tomber d'un coup ;
//   - la lumière faiblit avec la distance au joueur (vignettage qui commence tôt et doux) ;
//   - teinte nuit chaude-froide (pas d'aplat violet), légère brume animée.
// 5 lectures de texture (4 de fog_common + l'écran déjà dessiné). Ennemis et conteneurs hors
// vue restent cachés par FogOfWar (groupe fog_hideable), pas par ce shader.

#include "res://assets/shaders/fog_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// Décor hors vue : teinte multiplicative (nuit), plancher (jamais de noir pur).
uniform vec4 shade_tint : source_color = vec4(0.7, 0.76, 1.0, 1.0);
uniform vec4 shade_floor : source_color = vec4(0.03, 0.035, 0.06, 1.0);
// Zones explorées / jamais vues : luminosité et saturation restantes.
uniform float explored_brightness : hint_range(0.0, 1.0) = 0.5;
uniform float explored_saturation : hint_range(0.0, 1.0) = 0.42;
uniform float unseen_brightness : hint_range(0.0, 1.0) = 0.14;
uniform float unseen_saturation : hint_range(0.0, 1.0) = 0.15;
// Pénombre : part de lumière gardée dans le halo juste au-delà du bord (0..1), et courbe.
uniform float penumbra_light : hint_range(0.0, 1.0) = 0.55;
uniform float penumbra_curve : hint_range(0.3, 4.0) = 1.6;
// Brume légère par-dessus (plus présente loin du joueur).
uniform vec4 mist_color : source_color = vec4(0.2, 0.24, 0.38, 1.0);
uniform float mist_density : hint_range(0.0, 1.0) = 0.16;
// Chaleur de la zone éclairée près du bord (lumière qui faiblit en se réchauffant légèrement).
uniform vec4 dusk_color : source_color = vec4(1.0, 0.86, 0.72, 1.0);
uniform float dusk_strength : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	FogSample s = fog_sample(world_pos, TIME);
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;

	// Décor hors vue : nuit désaturée, plus lisible si exploré.
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	float sat = mix(unseen_saturation, explored_saturation, s.memory);
	float bright = mix(unseen_brightness, explored_brightness, s.memory);
	vec3 dark = shade_floor.rgb + mix(vec3(lum), scene, sat) * shade_tint.rgb * bright;
	float mist = s.wisp * mist_density * (0.6 + 0.4 * smoothstep(0.4, 1.2, s.dist));
	dark = mix(dark, mist_color.rgb * (0.75 + 0.4 * s.n1), mist);

	// Pénombre : juste au-delà du bord, une partie de la lumière subsiste et décroît.
	float pen = pow(clamp(s.halo, 0.0, 1.0), penumbra_curve) * penumbra_light;
	vec3 lit = mix(scene, scene * dusk_color.rgb, dusk_strength * smoothstep(0.35, 1.0, s.dist));
	float light = max(s.vis, pen);
	vec3 col = mix(dark, lit, light);
	COLOR = vec4(col, 1.0);
}
