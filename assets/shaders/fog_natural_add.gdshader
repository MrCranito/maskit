shader_type canvas_item;
render_mode blend_premul_alpha;
// Brouillard « naturel », passe 2 / 2 (additive) : + B (plancher nuit, gris de désaturation,
// brume), posée sur la passe multiplicative fog_natural.gdshader. Alpha 0 en mélange prémultiplié :
// image = B + décor. Voir fog_natural_common.gdshaderinc.

#include "res://assets/shaders/fog_natural_common.gdshaderinc"

void fragment() {
	vec3 f;
	vec3 b;
	natural_terms(world_pos, TIME, f, b);
	COLOR = vec4(b, 0.0);
}
