shader_type canvas_item;
// Séquence de mort (scripts/ui/death_overlay.gd) : le monde se désature et s'assombrit,
// sauf un halo autour du héros abattu ; vignette rouge sur les bords.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// 0 = image normale, 1 = effet complet.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Position du héros (UV écran) et rayon du halo net (en hauteur d'écran).
uniform vec2 focus = vec2(0.5, 0.5);
uniform float focus_radius = 0.16;
uniform float darken : hint_range(0.0, 1.0) = 0.55;
uniform float vignette : hint_range(0.0, 1.0) = 0.7;
uniform vec4 vignette_color : source_color = vec4(0.62, 0.04, 0.09, 1.0);
uniform float aspect = 1.7778;

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	vec2 d = (SCREEN_UV - focus) * vec2(aspect, 1.0);
	float away = smoothstep(focus_radius, focus_radius + 0.38, length(d));
	// Désaturation (un peu plus froide loin du héros), assombrissement hors du halo.
	vec3 cold = vec3(gray) * vec3(0.82, 0.86, 1.0);
	col = mix(col, cold, amount * mix(0.6, 1.0, away));
	col *= 1.0 - darken * amount * away;
	// Vignette rouge (bords de l'écran).
	vec2 c = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float edge = smoothstep(0.45, 1.05, length(c));
	col = mix(col, vignette_color.rgb, clamp(edge * vignette * amount, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
