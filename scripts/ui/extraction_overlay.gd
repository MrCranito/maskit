class_name ExtractionOverlay
extends CanvasLayer
## Calque plein écran de l'extraction (créé par Raid pendant la canalisation) :
##   - vignette verte sur les bords, qui pulse et s'intensifie avec la progression ;
##   - compte à rebours géant en Anton (« EXTRACTION » + secondes restantes), qui « claque » à
##     chaque seconde ;
##   - flash final (play_success) : voile vert-blanc qui monte puis retombe, texte « EXTRAIT ».
## Réglages : balance.cfg [extraction] overlay_*.

const COL := ExtractionZone.COL
const VIGNETTE: Texture2D = preload("res://assets/ui/menu/vignette.png")

var _vignette: TextureRect = null
var _title: Label = null
var _count: Label = null
var _flash: ColorRect = null
var _shown_secs: int = -1
var _pulse_t: float = 0.0
var _progress: float = 0.0


func _ready() -> void:
	name = "ExtractionOverlay"
	layer = int(Balance.get_value("extraction", "overlay_layer", 30))
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_vignette = TextureRect.new()
	_vignette.texture = VIGNETTE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(COL, 0.0)
	root.add_child(_vignette)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.offset_top = Balance.get_float("extraction", "overlay_top", 96.0)
	col.offset_left = -200.0
	col.offset_right = 200.0
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", -10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	_title = MenuKit.label("EXTRACTION", 22, COL, MenuKit.nunito(900), 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	col.add_child(_title)
	_count = MenuKit.label("", int(Balance.get_value("extraction", "overlay_count_size", 96)), MenuKit.TEXT, MenuKit.display(), 10)
	_count.name = "Countdown"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_color_override("font_outline_color", Color(0.02, 0.07, 0.07, 0.85))
	col.add_child(_count)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 1.0, 0.9, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


## p = 0..1, remaining = secondes restantes.
func set_progress(p: float, remaining: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	var secs := ceili(maxf(remaining, 0.0))
	if secs != _shown_secs and _count != null:
		_shown_secs = secs
		_count.text = str(secs)
		_count.pivot_offset = _count.size * 0.5
		_count.scale = Vector2(1.45, 1.45)
		_count.modulate = Color(COL.lightened(0.5), 1.0)
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_count, "scale", Vector2.ONE, 0.32)
		tw.tween_property(_count, "modulate", Color.WHITE, 0.4)


func _process(delta: float) -> void:
	if _vignette == null:
		return
	# Pulsation qui accélère avec la progression.
	_pulse_t += delta * lerpf(2.5, 7.0, _progress)
	var base := lerpf(0.25, 0.75, _progress)
	_vignette.modulate.a = base * (0.8 + 0.2 * sin(_pulse_t))


## Texte affiché par le compte à rebours (tests).
func get_count_text() -> String:
	return _count.text if _count != null else ""


## Flash final : le voile monte puis retombe, le compte à rebours devient « EXTRAIT ».
func play_success(duration: float) -> void:
	if _count == null:
		return
	_title.visible = false
	_count.text = "EXTRAIT"
	_count.pivot_offset = _count.size * 0.5
	_count.scale = Vector2(1.6, 1.6)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_count, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_vignette, "modulate:a", 1.0, duration * 0.3)
	var fl := create_tween()
	fl.tween_property(_flash, "color:a", Balance.get_float("extraction", "overlay_flash_alpha", 0.85), duration * 0.45) \
		.set_delay(duration * 0.2).set_ease(Tween.EASE_IN)
	fl.tween_property(_flash, "color:a", 0.0, duration * 0.35)
