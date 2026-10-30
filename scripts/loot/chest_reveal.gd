class_name ChestReveal
extends Node2D
## Effet d'ouverture d'un conteneur (maquette « Butin révélé ») : un faisceau de lumière à la
## couleur de la meilleure rareté monte du conteneur, puis les objets les plus rares jaillissent
## en arc au-dessus (icône dans une pastille encre cerclée de leur rareté, lueur pour Épique et
## Légendaire), restent un instant et s'effacent. Purement visuel : la fenêtre de butin s'ouvre
## en même temps. Animé par Tweens uniquement (aucun _process), se libère tout seul.
## Réglages : data/balance.cfg [loot] reveal_*.

const ICON_PX := 26.0

var _entries: Array[Dictionary] = []
var _top: float = 40.0
var _beam_color: Color = Color.WHITE


## `entries` : contenu tiré ({item: ItemData, count}) ; `top` : hauteur visuelle du conteneur (px).
static func create(entries: Array[Dictionary], top: float) -> ChestReveal:
	var r := ChestReveal.new()
	r._entries = entries
	r._top = top
	return r


## Les `n` objets à montrer : rareté décroissante, puis valeur décroissante.
static func pick(entries: Array[Dictionary], n: int) -> Array[ItemData]:
	var items: Array[ItemData] = []
	for e: Dictionary in entries:
		var it: ItemData = e.get("item") as ItemData
		if it != null:
			items.append(it)
	items.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		return a.rarity > b.rarity if a.rarity != b.rarity else a.value > b.value)
	return items.slice(0, n)


func _ready() -> void:
	name = "ChestReveal"
	z_as_relative = false
	z_index = 55
	var shown := pick(_entries, int(LootDB.geti("reveal_max_icons", 4)))
	if shown.is_empty():
		queue_free()
		return
	_beam_color = LootDB.rarity_color(shown[0].rarity)
	var dur: float = LootDB.getf("reveal_duration", 1.6)
	_build_beam(dur)
	_build_icons(shown, dur)
	get_tree().create_timer(dur + 0.4, false).timeout.connect(queue_free)


## Faisceau : trapèze en dégradé vertical (opaque en bas, transparent en haut).
func _build_beam(dur: float) -> void:
	var h: float = _top + LootDB.getf("reveal_beam_height", 90.0)
	var w0 := 16.0
	var w1 := 38.0
	var beam := Polygon2D.new()
	beam.name = "Beam"
	beam.polygon = PackedVector2Array([Vector2(-w0, -_top * 0.45), Vector2(w0, -_top * 0.45),
		Vector2(w1, -h), Vector2(-w1, -h)])
	var c := _beam_color
	beam.vertex_colors = PackedColorArray([Color(c, 0.8), Color(c, 0.8), Color(c, 0.0), Color(c, 0.0)])
	beam.modulate.a = 0.0
	add_child(beam)
	var tw := beam.create_tween()
	tw.tween_property(beam, "modulate:a", 1.0, 0.15)
	tw.tween_interval(dur * 0.45)
	tw.tween_property(beam, "modulate:a", 0.0, dur * 0.45)


## Icônes en arc au-dessus du conteneur, de la plus rare (au centre, en haut) aux autres.
func _build_icons(items: Array[ItemData], dur: float) -> void:
	var n := items.size()
	var lift: float = _top + LootDB.getf("reveal_icon_lift", 34.0)
	var spread: float = LootDB.getf("reveal_icon_spread", 34.0)
	# ordre d'affichage : la plus rare au centre, puis alternance gauche / droite
	var slots: Array[float] = []
	for i in n:
		var side := 1.0 if i % 2 == 1 else -1.0
		slots.append(0.0 if i == 0 else side * spread * ceilf(i / 2.0))
	for i in n:
		var it := items[i]
		var icon := RevealIcon.new()
		icon.item = it
		icon.position = Vector2(0, -_top * 0.5)
		icon.scale = Vector2.ZERO
		add_child(icon)
		var x: float = slots[i]
		var target := Vector2(x, -lift + absf(x) * 0.35)
		var tw := icon.create_tween()
		tw.tween_interval(0.12 + i * 0.09)
		tw.set_parallel(true)
		tw.tween_property(icon, "position", target, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(icon, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.set_parallel(false)
		tw.tween_interval(dur * 0.5)
		tw.tween_property(icon, "modulate:a", 0.0, 0.3)


## Pastille d'objet : disque encre, anneau de rareté, lueur pour Épique / Légendaire, icône.
class RevealIcon extends Node2D:
	var item: ItemData = null

	func _draw() -> void:
		if item == null:
			return
		var r := ChestReveal.ICON_PX * 0.5 + 4.0
		var col := LootDB.rarity_color(item.rarity)
		if item.rarity >= ItemData.Rarity.EPIC:
			for k in 3:
				draw_circle(Vector2.ZERO, r + 10.0 - k * 3.0, Color(col, 0.12 + k * 0.08))
		draw_circle(Vector2.ZERO, r, Color(MenuKit.NIGHT_DEEP, 0.85))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 2.5, true)
		var tex := LootVisuals.item_icon(item)
		if tex != null:
			var s := ChestReveal.ICON_PX
			draw_texture_rect(tex, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), false, LootVisuals.item_tint(item))
