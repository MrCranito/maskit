shader_type canvas_item;
// Verre dépoli (direction « D ») : le fond derrière l'élément est flouté puis teinté de la couleur
// de l'élément (COLOR, alpha = force de la teinte). Pour les bandeaux et panneaux des menus.
// Flou : mipmaps de l'écran (si disponibles) + 12 échantillons en couronne.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Rayon du flou en pixels d'écran et niveau de mipmap utilisé.
uniform float radius = 10.0;
uniform float lod = 2.5;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = textureLod(screen_tex, SCREEN_UV, lod).rgb * 2.0;
	float w = 2.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5235988;
		vec2 d = vec2(cos(a), sin(a));
		acc += textureLod(screen_tex, SCREEN_UV + d * px, lod).rgb;
		acc += textureLod(screen_tex, SCREEN_UV + d * px * 0.5, lod).rgb;
		w += 2.0;
	}
	vec3 bg = acc / w;
	COLOR = vec4(mix(bg, COLOR.rgb, COLOR.a), 1.0);
}
