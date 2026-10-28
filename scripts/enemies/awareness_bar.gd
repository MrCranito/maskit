class_name AwarenessBar
extends Node2D
## Jauge de reconnaissance au-dessus de la tête d'un ennemi (au-dessus de la barre de vie).
## Anneau épais sur pastille sombre qui se remplit dans le sens horaire, jaune → orange → rouge ;
## « ? » au centre à partir du palier de suspicion. Masquée à 0 et une fois l'ennemi « repéré »
## (le « ! » d'EnemyVisual.play_alert prend le relais).
##
## Performance : aucun _process ; redessin uniquement quand la valeur change d'au moins
## REDRAW_STEP ou qu'un palier / la visibilité change.

const RADIUS := 14.0
const THICKNESS := 6.0
## z absolu : au-dessus des toits (50) et du brouillard (80), sous l'UI (CanvasLayer).
## L'ennemi entier est masqué hors champ de vision (groupe fog_hideable), la jauge avec lui.
const Z_ABOVE_FOG := 90
const REDRAW_STEP := 0.02
const SEGMENTS := 28

const OUTLINE := Color(0.07, 0.06, 0.10, 0.95)
const BACKDROP := Color(0.12, 0.10, 0.16, 0.85)
const TRACK := Color(0.32, 0.24, 0.20, 0.9)
const COL_LOW := Color(1.0, 0.86, 0.25)
const COL_MID := Color(1.0, 0.55, 0.12)
const COL_HIGH := Color(0.95, 0.18, 0.10)
const GLYPH_DIM := Color(0.85, 0.80, 0.70, 0.55)
const GLYPH_HOT := Color(1.0, 0.95, 0.78)

var value: float = 0.0
var suspicion: float = 0.3
var _drawn_value: float = -1.0
var _drawn_suspicious: bool = false
var _font: Font = null


## `anchor` : centre de l'anneau (local à l'ennemi). `suspicion_level` : palier du « ? ».
func setup(anchor: Vector2, suspicion_level: float) -> void:
	position = anchor
	suspicion = suspicion_level
	z_as_relative = false
	z_index = Z_ABOVE_FOG
	visible = false
	_font = ThemeDB.fallback_font


## Met à jour la valeur 0..1. `show` = faux masque la jauge (ennemi repéré / mort).
func set_value(v: float, show: bool = true) -> void:
	value = clampf(v, 0.0, 1.0)
	var want_visible := show and value > 0.005 and value < 0.999
	if want_visible != visible:
		visible = want_visible
		_drawn_value = -1.0
	if not visible:
		return
	var suspicious := value >= suspicion
	if absf(value - _drawn_value) >= REDRAW_STEP or suspicious != _drawn_suspicious:
		queue_redraw()


## Couleur de remplissage selon la valeur : jaune → orange → rouge.
static func fill_color(v: float) -> Color:
	if v < 0.5:
		return COL_LOW.lerp(COL_MID, v / 0.5)
	return COL_MID.lerp(COL_HIGH, (v - 0.5) / 0.5)


func _draw() -> void:
	_drawn_value = value
	_drawn_suspicious = value >= suspicion
	var r_out := RADIUS + THICKNESS * 0.5
	# Pastille : contour sombre + fond.
	draw_circle(Vector2.ZERO, r_out + 2.0, OUTLINE)
	draw_circle(Vector2.ZERO, r_out, BACKDROP)
	# Piste vide puis remplissage (départ en haut, sens horaire).
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, SEGMENTS, TRACK, THICKNESS, true)
	var col := fill_color(value)
	var a0 := -PI * 0.5
	if value > 0.0:
		draw_arc(Vector2.ZERO, RADIUS, a0, a0 + TAU * value, maxi(4, int(SEGMENTS * value) + 2), col, THICKNESS, true)
		# Reflet chaud sur le bord intérieur de la partie remplie.
		draw_arc(Vector2.ZERO, RADIUS - THICKNESS * 0.35, a0, a0 + TAU * value, maxi(4, int(SEGMENTS * value) + 2),
			col.lerp(Color(1, 0.97, 0.85), 0.45), 1.2, true)
	# Glyphe central : « ? » vif dès la suspicion, sinon discret.
	if _font != null:
		var size := 20
		var glyph := "?"
		var gcol := GLYPH_HOT if _drawn_suspicious else GLYPH_DIM
		var w := _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var base := Vector2(-w * 0.5, size * 0.36)
		draw_string_outline(_font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, OUTLINE)
		draw_string(_font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size, gcol)
