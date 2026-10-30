// Partie commune des deux styles de brouillard (FogOfWar, [fog] fog_style) :
// masque de visibilité, mémoire d'exploration, bruit de brume, bord du champ de vision.
// 4 lectures de texture, sans boucle :
//   vis_mask     : SubViewport basse résolution. R = polygone de visibilité adouci (bord court),
//                  G = même polygone très adouci (halo large, dégradé depuis le bord ; 0 si inutilisé)
//   explored_map : mémoire d'exploration, 1 texel par case (filtrée = bords doux)
//   mist_noise   : bruit seamless (R = volutes larges, G = détail), lu 2 fois avec défilement
// Toutes les valeurs viennent de data/balance.cfg (FogOfWar._apply_shader_params).

uniform sampler2D vis_mask : filter_linear, repeat_disable;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D mist_noise : filter_linear, repeat_enable;

uniform vec2 map_size_px = vec2(2560.0, 1920.0);
uniform vec2 player_pos = vec2(0.0);
uniform float view_radius_px = 640.0;
uniform float reveal = 0.0;

uniform float mist_scale = 900.0;
uniform float mist_speed = 14.0;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.15;
uniform float edge_noise : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.7;
uniform float vignette_noise : hint_range(0.0, 0.5) = 0.08;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

struct FogSample {
	float vis;     // 1 = dans le champ de vision (net), 0 = hors vue
	float halo;    // dégradé large depuis le bord de vision (1 au bord, 0 loin)
	float memory;  // 1 = case déjà explorée
	float n1;      // bruit large
	float n2;      // bruit de détail
	float wisp;    // volutes de brume (0..1)
	float dist;    // distance au joueur / rayon de vue
};

FogSample fog_sample(vec2 wp, float time) {
	FogSample s;
	vec2 uv = wp / map_size_px;
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	vec2 mask = texture(vis_mask, uv).rg * inside;
	s.memory = texture(explored_map, uv).r * inside;
	// Brume : deux couches de bruit qui dérivent lentement en sens opposés.
	float t = time * mist_speed;
	s.n1 = texture(mist_noise, (wp + vec2(t, t * 0.35)) / mist_scale).r;
	s.n2 = texture(mist_noise, (wp - vec2(t * 0.6, -t * 0.8)) / (mist_scale * 0.42)).g;
	s.wisp = smoothstep(0.3, 0.85, s.n1 * 0.7 + s.n2 * 0.45);
	// Bord du champ de vision : masque adouci, légèrement déformé par la brume.
	float m = mask.r + (s.n2 - 0.5) * edge_noise * (1.0 - abs(mask.r * 2.0 - 1.0));
	float vis = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, m);
	// Vignettage circulaire (le champ de vision s'estompe à la limite du rayon de vue).
	s.dist = distance(wp, player_pos) / view_radius_px;
	float vig = 1.0 - smoothstep(vignette_start, 1.0, s.dist + (s.n1 - 0.5) * vignette_noise);
	s.vis = max(vis * vig, reveal);
	s.halo = mask.g * vig;
	return s;
}

// Bruit de hachage (grain fin, sans texture).
float fog_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
