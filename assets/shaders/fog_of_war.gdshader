shader_type canvas_item;
// Brouillard atmosphérique (FogOfWar). Un seul rectangle en espace monde (z 80) :
// suit exactement la caméra. Une passe, sans boucle, 4 lectures de texture :
//   vis_mask     : polygone de visibilité adouci (SubViewport basse résolution, canal R)
//   explored_map : mémoire d'exploration, 1 texel par case (filtrée = bords doux)
//   mist_noise   : bruit seamless (R = volutes larges, G = détail), lu 2 fois avec défilement
// Visible = masque × vignettage circulaire autour du joueur ; partout ailleurs, brume
// bleu nuit animée ; zone explorée hors vue = brume à peine moins dense (souvenir).

uniform sampler2D vis_mask : filter_linear, repeat_disable;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D mist_noise : filter_linear, repeat_enable;

uniform vec2 map_size_px = vec2(2560.0, 1920.0);
uniform vec2 player_pos = vec2(0.0);
uniform float view_radius_px = 640.0;
uniform float reveal = 0.0;

uniform vec4 fog_color : source_color = vec4(0.035, 0.05, 0.11, 1.0);
uniform vec4 mist_color : source_color = vec4(0.2, 0.25, 0.42, 1.0);
uniform vec4 penumbra_color : source_color = vec4(0.06, 0.08, 0.2, 1.0);
uniform float unseen_alpha : hint_range(0.0, 1.0) = 0.985;
uniform float memory_strength : hint_range(0.0, 1.0) = 0.12;
uniform float mist_density : hint_range(0.0, 1.0) = 0.55;
uniform float mist_scale = 900.0;
uniform float mist_speed = 14.0;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.22;
uniform float edge_noise : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.55;
// Brume résiduelle dans la zone visible (0 = nette), croît vers le bord de vision.
uniform float visible_haze : hint_range(0.0, 0.5) = 0.12;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / map_size_px;
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	float mask = texture(vis_mask, uv).r * inside;
	float memory = texture(explored_map, uv).r * inside;

	// Brume : deux couches de bruit qui dérivent lentement en sens opposés.
	float t = TIME * mist_speed;
	float n1 = texture(mist_noise, (world_pos + vec2(t, t * 0.35)) / mist_scale).r;
	float n2 = texture(mist_noise, (world_pos - vec2(t * 0.6, -t * 0.8)) / (mist_scale * 0.42)).g;
	float wisp = smoothstep(0.3, 0.85, n1 * 0.7 + n2 * 0.45);

	// Bord du champ de vision : masque adouci, déformé par la brume (organique).
	float m = mask + (n2 - 0.5) * edge_noise * (1.0 - abs(mask * 2.0 - 1.0));
	float vis = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, m);
	// Vignettage circulaire (pénombre en bord de vision).
	float d = distance(world_pos, player_pos) / view_radius_px;
	float vig = 1.0 - smoothstep(vignette_start, 1.0, d + (n1 - 0.5) * 0.12);
	vis *= vig;
	vis = max(vis, reveal);
	// Brume légère qui flotte même sur la zone visible (plus dense loin du joueur).
	float haze = visible_haze * wisp * smoothstep(0.15, 0.9, d) * (1.0 - reveal);

	// Densité de la brume : jamais vu ≈ opaque, exploré = souvenir très discret.
	float base_a = unseen_alpha - memory_strength * memory;
	float fog_a = clamp(base_a - wisp * mist_density * 0.06 + n2 * 0.02, 0.0, 1.0);
	vec3 col = mix(fog_color.rgb, mist_color.rgb, wisp * mist_density);
	// Crêtes des volutes très légèrement éclairées (volume), creux plus profonds.
	col += mist_color.rgb * smoothstep(0.55, 0.8, n1 * 0.6 + n2 * 0.5) * mist_density * 0.35;
	col *= 0.85 + 0.3 * n1;
	// Pénombre : les bords visibles se teintent de bleu nuit (ombres de la DA).
	float pen = vis * (1.0 - vis) * 4.0;
	col = mix(col, penumbra_color.rgb, pen * 0.5);
	float a = fog_a * (1.0 - vis) + haze * vis;
	col = mix(col, mist_color.rgb, haze * vis * 2.0);
	COLOR = vec4(col, a);
}
