shader_type canvas_item;
// Flash de coup réutilisable (héros et ennemis).
// flash_amount : 0 = rendu normal, 1 = silhouette entièrement flash_color.
// L'alpha de la texture et de modulate est conservé (le clignotement par modulate.a reste possible).
// Usage GDScript :
//   var mat := ShaderMaterial.new()
//   mat.shader = preload("res://assets/shaders/hit_flash.gdshader")
//   sprite.material = mat
//   mat.set_shader_parameter("flash_amount", 1.0)  # puis redescendre vers 0

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_amount * flash_color.a), tex.a);
}
