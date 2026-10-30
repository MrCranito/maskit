class_name MapZoom
extends RefCounted
## Calcul du cadrage de la carte plein écran (zoom + déplacement), sans nœud : testable seul.
## Repères : « monde » = coordonnées du contenu de la carte (px monde), « écran » = px locaux de
## la vue (origine en haut à gauche de la vue). écran = offset + monde × scale.
## Bornes : zoom min = carte entière visible (ajustée), zoom max = min × max_factor ;
## déplacement borné aux limites de la carte (centrée sur un axe plus petit que la vue).

## Taille de la vue (px écran).
var view_size: Vector2 = Vector2.ONE
## Rectangle monde de la carte entière.
var world: Rect2 = Rect2(0, 0, 1, 1)
## Zoom maximal en multiple du zoom « carte entière ».
var max_factor: float = 4.0
## Px écran par px monde.
var scale: float = 1.0
## Position écran de l'origine du monde.
var offset: Vector2 = Vector2.ZERO


func setup(p_view_size: Vector2, p_world: Rect2, p_max_factor: float) -> void:
	view_size = Vector2(maxf(p_view_size.x, 1.0), maxf(p_view_size.y, 1.0))
	world = Rect2(p_world.position, Vector2(maxf(p_world.size.x, 1.0), maxf(p_world.size.y, 1.0)))
	max_factor = maxf(p_max_factor, 1.0)
	reset()


## Nouvelle taille de vue : garde le point central et le facteur de zoom (bornés).
func resize(p_view_size: Vector2) -> void:
	var c := center_world()
	var f := zoom_factor()
	view_size = Vector2(maxf(p_view_size.x, 1.0), maxf(p_view_size.y, 1.0))
	scale = clampf(min_scale() * f, min_scale(), max_scale())
	center_on(c)


## Carte entière, centrée.
func reset() -> void:
	scale = min_scale()
	center_on(world.get_center())


func min_scale() -> float:
	return minf(view_size.x / world.size.x, view_size.y / world.size.y)


func max_scale() -> float:
	return min_scale() * max_factor


## Zoom relatif au zoom « carte entière » (1 = carte entière).
func zoom_factor() -> float:
	return scale / min_scale()


func is_min_zoom() -> bool:
	return scale <= min_scale() * 1.001


func is_max_zoom() -> bool:
	return scale >= max_scale() * 0.999


func world_to_screen(p: Vector2) -> Vector2:
	return offset + p * scale


func screen_to_world(s: Vector2) -> Vector2:
	return (s - offset) / scale


## Point monde au centre de la vue.
func center_world() -> Vector2:
	return screen_to_world(view_size * 0.5)


## Multiplie le zoom par `factor` en gardant fixe le point monde sous `screen_pt`.
func zoom_at(screen_pt: Vector2, factor: float) -> void:
	set_scale_at(screen_pt, scale * factor)


## Zoom absolu (borné) en gardant fixe le point monde sous `screen_pt`.
func set_scale_at(screen_pt: Vector2, new_scale: float) -> void:
	var w := screen_to_world(screen_pt)
	scale = clampf(new_scale, min_scale(), max_scale())
	offset = screen_pt - w * scale
	clamp_offset()


## Pincement : le point monde `anchor` (pris sous le milieu des doigts au début) suit le milieu
## courant `screen_pt` ; zoom absolu `new_scale` (borné).
func pinch(anchor: Vector2, screen_pt: Vector2, new_scale: float) -> void:
	scale = clampf(new_scale, min_scale(), max_scale())
	offset = screen_pt - anchor * scale
	clamp_offset()


## Déplace la vue de `delta` px écran ; renvoie le déplacement réellement appliqué (bornes).
func pan(delta: Vector2) -> Vector2:
	var before := offset
	offset += delta
	clamp_offset()
	return offset - before


## Centre la vue sur le point monde `p` (borné aux limites de la carte).
func center_on(p: Vector2) -> void:
	offset = view_size * 0.5 - p * scale
	clamp_offset()


## Axe plus petit que la vue : carte centrée ; sinon aucun bord de la carte ne rentre dans la vue.
func clamp_offset() -> void:
	var lo := view_size - world.end * scale
	var hi := -world.position * scale
	for i in 2:
		if world.size[i] * scale <= view_size[i]:
			offset[i] = (view_size[i] - world.size[i] * scale) * 0.5 - world.position[i] * scale
		else:
			offset[i] = clampf(offset[i], lo[i], hi[i])
