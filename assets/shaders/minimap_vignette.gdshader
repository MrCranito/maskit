shader_type canvas_item;
// Vignettage de la mini-carte (scripts/ui/minimap.gd) : assombrit doucement les bords du cadre
// (encre), sans texture ; dessiné par-dessus la carte, sous le cadre. Statique.

uniform vec4 ink : source_color = vec4(0.02, 0.02, 0.04, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.55;
// Début du dégradé (0 = centre, 1 = bord) et courbe.
uniform float start : hint_range(0.0, 1.0) = 0.55;
uniform float curve : hint_range(0.3, 4.0) = 1.6;

void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;
	// Carré arrondi : suit le cadre plutôt qu'un cercle.
	float r = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
	float v = pow(clamp((r - start) / max(1.0 - start, 0.001), 0.0, 1.0), curve);
	COLOR = vec4(ink.rgb, v * strength);
}
