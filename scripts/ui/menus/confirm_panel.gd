class_name ConfirmPanel
extends ModalPanel
## Fenêtre de confirmation : message + « Annuler » / bouton d'action (rouge si `danger`).
## Signal `confirmed` (puis fermeture). Échap / clic sur le voile = annuler.

signal confirmed

var message: String = ""
var confirm_text: String = "Confirmer"
var danger: bool = false
var confirm_button: Button = null
var extra: Control = null


func _init(title_text: String = "", p_message: String = "", p_confirm: String = "Confirmer",
		p_danger: bool = false, p_extra: Control = null) -> void:
	super._init(title_text, Vector2(560, 0))
	message = p_message
	confirm_text = p_confirm
	danger = p_danger
	extra = p_extra


func _build_body() -> void:
	close_button.text = "Annuler"
	close_button.custom_minimum_size = Vector2(200, 68)
	if extra != null:
		extra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(extra)
	var l := MenuKit.label(message, 21, MenuKit.TEXT, MenuKit.nunito(750))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(480, 0)
	body.add_child(l)
	# « Annuler » et l'action côte à côte
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	close_button.get_parent().add_child(row)
	close_button.reparent(row)
	confirm_button = MenuKit.button(confirm_text, MenuKit.Style.PRIMARY, 24, Vector2(240, 68))
	row.add_child(confirm_button)
	confirm_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"confirm")
		confirmed.emit()
		close())


func _focus_first() -> void:
	if is_inside_tree() and confirm_button != null:
		(close_button if danger else confirm_button).grab_focus()
