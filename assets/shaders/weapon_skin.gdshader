shader_type canvas_item;
// Skin d'arme (WeaponSkin.apply) : recoloration qui garde l'ombrage peint du sprite (luminance
// → rampe de teintes du skin), les contours sombres et les reflets, + motif procédural net.
// Motifs en coordonnées « longueur de l'arme » (UV.x de 0 à 1 = crosse → canon) : même rendu
// sur l'arme tenue (≈124×40) et sur l'icône (256×128).
// Aucun TIME : rendu statique (aucun redessin forcé). Coût : 1 lecture de texture (+4 pour le
// néon, +8 si glow > 0 : légendaires).

uniform vec4 color_primary : source_color = vec4(1.0);
uniform vec4 color_secondary : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color_accent : source_color = vec4(1.0);
// 0 aucun, 1 rayures, 2 camouflage, 3 numérique, 4 or, 5 néon, 6 carbone, 7 tigre, 8 flammes, 9 rouille
uniform int pattern = 0;
// Nombre de cellules de motif sur la longueur de l'arme ; aspect = largeur / hauteur de l'image.
uniform float pattern_scale = 9.0;
uniform float aspect = 2.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// Rayon de la lueur, en fraction de la hauteur de l'image.
uniform float glow_radius = 0.035;
// Force de la recoloration (0 = sprite d'origine, utile pour la lueur seule).
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

float fbm(vec2 p) {
	return vnoise(p) * 0.62 + vnoise(p * 2.13 + 5.7) * 0.28 + vnoise(p * 4.7 + 1.3) * 0.10;
}

// Rampe de teinte façon peinture toon : ombre bleutée → teinte → lumière chaude.
vec3 toon_ramp(vec3 c, float l) {
	vec3 shadow = c * vec3(0.32, 0.34, 0.48);
	vec3 lit = min(c * 1.22 + vec3(0.06, 0.05, 0.02), vec3(1.0));
	return l < 0.5 ? mix(shadow, c, smoothstep(0.08, 0.5, l)) : mix(c, lit, smoothstep(0.5, 0.86, l));
}

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	// Contours sombres du sprite gardés tels quels (lisibilité).
	float ink = 1.0 - smoothstep(0.025, 0.07, lum);
	// Coordonnées : x le long de l'arme, y en mêmes unités.
	vec2 q = vec2(UV.x, UV.y / max(aspect, 0.1)) * pattern_scale;
	// Luminance remappée (les sprites peints sont sombres) pour la rampe.
	float l = pow(smoothstep(0.03, 0.58, lum), 0.7);
	vec3 col;
	vec3 emit = vec3(0.0);
	if (pattern == 1) {
		// Rayures diagonales franches
		float s = step(0.5, fract((q.x + q.y) * 0.6));
		col = toon_ramp(mix(color_primary.rgb, color_secondary.rgb, s), l);
	} else if (pattern == 2) {
		// Camouflage : taches organiques à bords nets (bruit déformé), quatre tons
		vec2 w = q * 0.55 + vec2(fbm(q * 0.6 + 3.1), fbm(q * 0.6 + 8.4)) * 1.3;
		float n = fbm(w);
		float n2 = vnoise(w * 1.7 + 11.0);
		vec3 c = color_primary.rgb;
		if (n < 0.40) c = color_secondary.rgb;
		else if (n > 0.62) c = color_accent.rgb;
		if (n2 > 0.74) c = mix(color_secondary.rgb, vec3(0.0), 0.45);
		col = toon_ramp(c, l);
	} else if (pattern == 3) {
		// Numérique : pixels francs groupés en amas (deux échelles de blocs)
		vec2 cell = floor(q * 2.4);
		float big = hash(floor(cell / 3.0) + 0.37);
		float small = hash(cell + 1.7);
		float n = big * 0.6 + small * 0.4;
		vec3 c = n < 0.36 ? color_secondary.rgb : (n < 0.64 ? color_primary.rgb : color_accent.rgb);
		col = toon_ramp(c, l);
	} else if (pattern == 4) {
		// Or massif : rampe métallique très contrastée + reflets en bandes le long de l'arme
		vec3 deep = color_secondary.rgb;
		vec3 gold = color_primary.rgb;
		vec3 pale = color_accent.rgb;
		float band = smoothstep(0.55, 0.95, sin(UV.x * 15.0 + UV.y * 9.0 - lum * 4.0) * 0.5 + 0.5);
		float lm = clamp(l * 1.1 + band * 0.25, 0.0, 1.0);
		col = lm < 0.45 ? mix(deep * 0.6, gold * 0.85, smoothstep(0.0, 0.45, lm)) : mix(gold, pale, smoothstep(0.55, 1.0, lm));
		// éclats spéculaires sur les arêtes claires
		col += pale * smoothstep(0.62, 0.85, lum) * 0.55;
	} else if (pattern == 5) {
		// Néon : corps noir satiné + filets lumineux (bords intérieurs + lignes de carrosserie)
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		float a1 = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
		float a2 = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
		float a3 = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
		float a4 = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		float edge = clamp((4.0 - (a1 + a2 + a3 + a4)) * 0.8, 0.0, 1.0) * step(0.5, tex.a);
		float lines = step(0.9, fract(q.x * 0.35 + q.y * 0.9)) * step(0.3, lum);
		float neon = max(edge, lines * 0.85);
		vec3 body = toon_ramp(color_secondary.rgb, l * 0.8);
		vec3 nc = mix(color_primary.rgb, color_accent.rgb, smoothstep(0.2, 0.8, UV.x));
		col = mix(body, nc * 1.25, neon);
		emit = nc * neon * 0.35;
		ink *= 1.0 - neon;
	} else if (pattern == 6) {
		// Carbone : tissage en damier avec lustre
		vec2 c = q * 2.2;
		float chk = mod(floor(c.x) + floor(c.y), 2.0);
		float g = chk > 0.5 ? fract(c.x) : fract(c.y);
		vec3 base = mix(color_secondary.rgb, color_primary.rgb, 0.25 + 0.75 * sin(g * 3.14159));
		base += color_accent.rgb * 0.25 * smoothstep(0.75, 1.0, sin(g * 3.14159));
		col = toon_ramp(base, l);
	} else if (pattern == 7) {
		// Tigre : bandes noires transversales effilées, ondulées, sur pelage orange
		float wv = fbm(vec2(q.x * 0.4, q.y * 1.4)) * 1.6 + q.y * 0.35;
		float s = sin((q.x * 2.1 + wv) * 3.14159);
		float width = 0.55 + 0.35 * vnoise(vec2(q.x * 0.7, 3.3));
		float stripe = smoothstep(width, width + 0.08, s);
		vec3 fur = mix(color_primary.rgb, color_accent.rgb, smoothstep(0.55, 0.9, vnoise(q * 0.8 + 2.0)));
		col = toon_ramp(mix(fur, color_secondary.rgb, stripe), l);
	} else if (pattern == 8) {
		// Flammes « hot rod » : langues pointues qui partent de l'avant vers la crosse
		float y = q.y * 0.6;
		float tri = abs(fract(y + fbm(vec2(q.x * 0.5, y)) * 0.35) - 0.5) * 2.0;   // 0 au centre d'une langue
		float edge_x = 0.28 + 0.32 * tri + 0.06 * vnoise(q * 1.5);
		float inside = smoothstep(edge_x - 0.012, edge_x + 0.012, UV.x);
		float heat = smoothstep(edge_x, edge_x + 0.42, UV.x);
		vec3 flame = mix(color_primary.rgb, color_accent.rgb, heat);
		vec3 body = toon_ramp(color_secondary.rgb, l);
		float rim = smoothstep(0.0, 0.03, abs(UV.x - edge_x));
		col = mix(body, mix(flame * 0.75, flame * 1.15, l), inside);
		col *= mix(0.25, 1.0, rim);
		emit = flame * inside * heat * 0.12;
	} else if (pattern == 9) {
		// Rouille : métal terne, plaques de rouille et piqûres, arêtes usées claires
		float n = fbm(q * 0.9 + 4.0);
		float pits = step(0.83, hash(floor(q * 6.0)));
		vec3 c = mix(color_secondary.rgb, color_primary.rgb, smoothstep(0.42, 0.52, n));
		c = mix(c, color_primary.rgb * 0.55, pits * 0.6);
		col = toon_ramp(c, l);
		col = mix(col, color_accent.rgb, smoothstep(0.6, 0.8, lum) * 0.6);
	} else {
		col = toon_ramp(color_primary.rgb, l);
		col = mix(col, color_accent.rgb, smoothstep(0.7, 0.9, lum) * 0.5);
	}
	col = mix(col, tex.rgb, ink) + emit;
	vec4 outc = vec4(mix(tex.rgb, col, strength), tex.a);
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
		float ga = (a - outc.a) * glow * 0.85;
		float na = max(outc.a, ga);
		outc.rgb = mix(color_accent.rgb, outc.rgb, outc.a / max(na, 0.001));
		outc.a = na;
	}
	COLOR = outc * v_modulate;
}
