shader_type canvas_item;
// Brume d'exploration de la mini-carte et de la carte plein écran (scripts/ui/minimap.gd).
// TEXTURE = mémoire d'exploration de FogOfWar (1 texel par case, L8, mise à jour par événement
// quand des cases sont découvertes, partagée avec le brouillard du jeu : aucune copie).
// Au lieu d'étirer ce masque (escaliers / blocs flous), on le lit en B-spline bicubique
// (4 lectures bilinéaires : surface lisse, contours arrondis), on déforme le seuil par un bruit
// en coordonnées de case (bord organique, fixe : il ne « nage » pas quand la carte défile),
// puis on découpe avec un fondu de largeur constante à l'écran (fwidth) et un liseré clair.
// Comme le brouillard « naturel » du jeu : rien n'est coupé net, teinte nuit froide, voile
// de brume léger. Hors de la grille (marge du sprite) : non exploré.
// Coût : 4 lectures de texture + bruit de valeur, sur les seuls pixels de la carte.

uniform vec4 fog_color : source_color = vec4(0.035, 0.045, 0.085, 1.0);
uniform vec4 mist_color : source_color = vec4(0.16, 0.19, 0.32, 1.0);
uniform float mist_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(0.72, 0.61, 1.0, 0.55);
// Liseré : largeur (px écran) et décalage vers la brume (unités du masque).
uniform float rim_px : hint_range(0.0, 6.0) = 1.4;
uniform float rim_offset : hint_range(0.0, 0.5) = 0.08;
// Seuil du masque lissé (0..1), fondu minimal (unités du masque) + fondu en px écran.
uniform float threshold : hint_range(0.05, 0.95) = 0.42;
uniform float edge_soft : hint_range(0.0, 0.5) = 0.06;
uniform float edge_px : hint_range(0.0, 4.0) = 1.0;
// Bord irrégulier : amplitude (unités du masque) et taille du motif (cases).
uniform float noise_amp : hint_range(0.0, 0.5) = 0.13;
uniform float noise_cells : hint_range(0.25, 8.0) = 1.6;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec4 cubic_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// B-spline bicubique en 4 lectures bilinéaires (texture en filtre linéaire) : coordonnées des
// 4 lectures (o.xz, o.yz, o.xw, o.yw) et poids de mélange (w.x horizontal, w.y vertical).
// (TEXTURE ne peut pas être passé à une fonction : les lectures se font dans fragment().)
void bspline_taps(vec2 uv, vec2 ts, out vec4 o, out vec2 w) {
	vec2 inv = 1.0 / ts;
	vec2 p = uv * ts - 0.5;
	vec2 f = fract(p);
	p -= f;
	vec4 xc = cubic_w(f.x);
	vec4 yc = cubic_w(f.y);
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	o = (c + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
	w = vec2(s.x / (s.x + s.y), s.z / (s.z + s.w));
}
void fragment() {
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	vec2 cell = UV * ts;
	float inside = step(0.0, UV.x) * step(0.0, UV.y) * step(UV.x, 1.0) * step(UV.y, 1.0);
	vec4 o;
	vec2 w;
	bspline_taps(clamp(UV, vec2(0.0), vec2(1.0)), ts, o, w);
	float s0 = texture(TEXTURE, o.xz).r;
	float s1 = texture(TEXTURE, o.yz).r;
	float s2 = texture(TEXTURE, o.xw).r;
	float s3 = texture(TEXTURE, o.yw).r;
	float e = mix(mix(s3, s2, w.x), mix(s1, s0, w.x), w.y) * inside;
	e += (vnoise(cell / noise_cells) - 0.5) * 2.0 * noise_amp * smoothstep(0.02, 0.2, e);
	float aa = max(fwidth(e), 1e-4);
	float soft = edge_soft + aa * edge_px;
	float seen = smoothstep(threshold - soft, threshold + soft, e);
	// Liseré : fine ligne claire juste côté brume.
	float d = (e - (threshold - rim_offset)) / (aa * max(rim_px, 0.01));
	float rim = exp(-d * d) * (1.0 - seen * 0.6) * step(0.001, rim_px);
	// Brume : voile légèrement nuageux (fixe), plus dense loin des zones vues.
	float m = vnoise(cell / 5.0) * 0.6 + vnoise(cell / 2.1) * 0.4;
	vec3 fog = mix(fog_color.rgb, mist_color.rgb, m * mist_amount * (1.0 - smoothstep(0.0, threshold, e) * 0.5));
	float a = fog_color.a * (1.0 - seen);
	vec3 col = mix(fog, rim_color.rgb, rim * rim_color.a);
	COLOR = vec4(col, max(a, rim * rim_color.a));
}
