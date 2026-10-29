class_name HudSafeArea
extends RefCounted
## Marges de sécurité du HUD (encoche, coins arrondis, barre d'accueil de l'iPhone), en
## coordonnées du viewport (stretch « canvas_items » + aspect « expand » : le viewport visible
## fait 720 px de haut et s'élargit avec l'écran).
##   marge = max([hud] safe_min_margin, encart de DisplayServer.get_display_safe_area() converti)
## Sur PC (pas d'encoche) : seulement la marge minimale. `debug_insets` (px de la fenêtre :
## gauche, haut, droite, bas) simule un téléphone pour les captures et les tests.
## Les éléments du HUD se recalent sur le signal size_changed du viewport.

## Encarts simulés en pixels de fenêtre (x gauche, y haut, z droite, w bas) ; négatif = inactif.
static var debug_insets: Vector4 = Vector4(-1, -1, -1, -1)


## Marges (gauche, haut, droite, bas) en coordonnées du viewport de `node`.
static func margins(node: Node) -> Vector4:
	var m := Balance.get_float("hud", "safe_min_margin", 16.0)
	var out := Vector4(m, m, m, m)
	if node == null or not node.is_inside_tree():
		return out
	var vp := node.get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		win = vp  # headless : pas de fenêtre, encarts déjà en px du viewport
	var insets := Vector4.ZERO
	if debug_insets.x >= 0.0:
		insets = debug_insets
	elif OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x <= 0 or win.x <= 0.0:
			return out
		insets = Vector4(safe.position.x, safe.position.y, win.x - safe.end.x, win.y - safe.end.y)
	else:
		return out
	if win.x <= 0.0 or win.y <= 0.0:
		return out
	var k := vp / win
	var extra := Balance.get_float("hud", "safe_extra_margin", 6.0)
	out.x = maxf(m, insets.x * k.x + (extra if insets.x > 0.0 else 0.0))
	out.y = maxf(m, insets.y * k.y + (extra if insets.y > 0.0 else 0.0))
	out.z = maxf(m, insets.z * k.x + (extra if insets.z > 0.0 else 0.0))
	out.w = maxf(m, insets.w * k.y + (extra if insets.w > 0.0 else 0.0))
	return out


## Rectangle sûr du viewport (zone où le HUD peut se placer).
static func safe_rect(node: Node) -> Rect2:
	var vp := node.get_viewport().get_visible_rect().size if node != null and node.is_inside_tree() else Vector2(1280, 720)
	var m := margins(node)
	return Rect2(Vector2(m.x, m.y), vp - Vector2(m.x + m.z, m.y + m.w))
