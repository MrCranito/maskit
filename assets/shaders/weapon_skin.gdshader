shader_type canvas_item;
// Skin d'arme (WeaponSkin.apply) : recoloration qui garde l'ombrage du sprite
// (luminance × couleurs du skin) + motif procédural léger + lueur de contour optionnelle.
// Aucun TIME : rendu statique (pas de redessin forcé). Coût : 1 lecture de texture,
// + 8 lectures seulement si glow > 0 (légendaires, néon).

uniform vec4 color_primary : source_color = vec4(1.0);
uniform vec4 color_secondary : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color_accent : source_color = vec4(1.0);
// 0 aucun, 1 rayures, 2 camouflage, 3 numérique, 4 doré, 5 néon, 6 carbone
uniform int pattern = 0;
// Cellules de motif sur la hauteur de l'image ; aspect = largeur / hauteur de l'image.
uniform float pattern_scale = 5.0;
uniform float aspect = 2.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// Rayon de la lueur, en fraction de la hauteur de l'image.
uniform float glow_radius = 0.035;
// Force de la recoloration (0 = sprite d'origine).
uniform float strength : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Couleur de sommet (modulate), sans la texture (COLOR du fragment l'inclut déjà).
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec2 p = UV * vec2(aspect, 1.0) * pattern_scale;
	vec3 base = color_primary.rgb;
	// Ombrage gardé mais remonté (les sprites peints sont sombres) : 0,4 → 1,25
	float shade = mix(0.4, 1.25, smoothstep(0.02, 0.62, lum));
	if (pattern == 1) {
		// Rayures diagonales franches
		float s = step(0.5, fract((p.x + p.y) * 0.5));
		base = mix(color_primary.rgb, color_secondary.rgb, s);
	} else if (pattern == 2) {
		// Camouflage : deux octaves de bruit, trois teintes
		float n = vnoise(p * 0.9) * 0.7 + vnoise(p * 2.1 + 7.3) * 0.3;
		base = n < 0.42 ? color_secondary.rgb : (n < 0.6 ? color_primary.rgb : color_accent.rgb);
	} else if (pattern == 3) {
		// Numérique : bruit par blocs
		float n = hash(floor(p * 2.0)) * 0.6 + hash(floor(p * 0.7) + 3.1) * 0.4;
		base = n < 0.38 ? color_secondary.rgb : (n < 0.66 ? color_primary.rgb : color_accent.rgb);
	} else if (pattern == 4) {
		// Doré : dégradé métallique + reflet spéculaire
		base = mix(color_secondary.rgb, color_primary.rgb, smoothstep(0.05, 0.55, lum));
		base += color_accent.rgb * smoothstep(0.45, 0.9, lum) * 0.6;
		shade = mix(0.65, 1.2, smoothstep(0.02, 0.6, lum));
	} else if (pattern == 5) {
		// Néon : corps sombre + filets lumineux
		float line = step(0.82, fract(p.x * 0.8 + p.y * 0.25));
		base = mix(color_secondary.rgb, color_primary.rgb, line);
		shade = mix(mix(0.6, 1.3, smoothstep(0.02, 0.6, lum)), 1.3, line);
	} else if (pattern == 6) {
		// Carbone : tissage en damier
		vec2 c = p * 3.0;
		float chk = mod(floor(c.x) + floor(c.y), 2.0);
		float g = chk > 0.5 ? fract(c.x) : fract(c.y);
		base = mix(color_secondary.rgb, color_primary.rgb, 0.35 + 0.65 * g);
	}
	vec3 col = base * shade;
	col += color_accent.rgb * smoothstep(0.78, 1.0, lum) * 0.35;
	vec4 outc = vec4(mix(tex.rgb, col, strength * tex.a), tex.a);
	if (glow > 0.0 && outc.a < 0.99) {
		// Lueur de contour : alpha voisin (8 lectures)
		vec2 r = vec2(glow_radius / aspect, glow_radius);
		float a = 0.0;
		a = max(a, texture(TEXTURE, UV + vec2(r.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV - vec2(r.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0, r.y)).a);
		a = max(a, texture(TEXTURE, UV - vec2(0.0, r.y)).a);
		a = max(a, texture(TEXTURE, UV + r * 0.7).a);
		a = max(a, texture(TEXTURE, UV - r * 0.7).a);
		a = max(a, texture(TEXTURE, UV + vec2(r.x, -r.y) * 0.7).a);
		a = max(a, texture(TEXTURE, UV + vec2(-r.x, r.y) * 0.7).a);
		float ga = (a - outc.a) * glow;
		float na = max(outc.a, ga);
		outc.rgb = mix(color_accent.rgb, outc.rgb, outc.a / max(na, 0.001));
		outc.a = na;
	}
	COLOR = outc * v_modulate;
}
