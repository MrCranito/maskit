shader_type canvas_item;
// Shader des sprites ennemis (EnemyVisual) : flash blanc au coup, teinte d'aura,
// lueur rouge de télégraphe d'attaque et dissolution à la mort.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
// rgb = couleur d'aura, a = force de la teinte (légère).
uniform vec4 aura_tint : source_color = vec4(1.0, 0.4, 0.2, 0.0);
uniform float windup : hint_range(0.0, 1.0) = 0.0;
uniform vec4 windup_color : source_color = vec4(1.0, 0.18, 0.1, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(1.0, 0.55, 0.25, 1.0);
// Taille des éclats de dissolution (cellules d'UV).
uniform float dissolve_cells = 22.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Teinte d'aura : multiplie légèrement, garde les lumières.
	vec3 tinted = c.rgb * mix(vec3(1.0), aura_tint.rgb * 1.3, aura_tint.a);
	c.rgb = tinted;
	// Télégraphe : lueur rouge qui monte du bas vers le haut.
	// Lueur rouge qui monte du bas vers le haut, plus forte sur les zones claires
	// pour conserver le modelé.
	float rise = smoothstep(1.0 - windup * 1.2, 1.0 - windup * 1.2 + 0.35, UV.y);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float k = windup * (0.12 + 0.3 * rise);
	c.rgb = mix(c.rgb, c.rgb * windup_color.rgb * 1.6 + windup_color.rgb * 0.15, k * 0.9);
	c.rgb += windup_color.rgb * k * (0.25 + lum * 0.5);
	// Flash blanc.
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	// Dissolution en éclats (du haut vers le bas) avec bord lumineux.
	if (dissolve > 0.0) {
		float n = hash(floor(UV * dissolve_cells)) * 0.6 + (1.0 - UV.y) * 0.4;
		float t = dissolve * 1.15;
		if (n < t) {
			discard;
		}
		float edge = 1.0 - smoothstep(0.0, 0.08, n - t);
		c.rgb = mix(c.rgb, dissolve_edge.rgb, edge * 0.8);
	}
	COLOR = c;
}
