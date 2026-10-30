class_name FrameRate
extends RefCounted
## Images par seconde du jeu (réglage « Images par seconde » des Options).
##  - « max » (par défaut) : la fréquence de l'écran, plafonnée à [display] max_fps_cap (120) —
##    120 i/s sur les téléphones à écran 120 Hz (iPhone Pro ProMotion, Android 120 Hz), 60 sinon ;
##  - « 60 » : 60 i/s ;
##  - « eco » : économie d'énergie, [display] eco_fps (30) i/s (moins de chauffe et de batterie).
## La logique du jeu reste à 60 pas de physique par seconde : l'interpolation physique
## (physics/common/physics_interpolation) rend les déplacements fluides à 120 i/s.
## iOS : l'écran 120 Hz est déverrouillé dans le projet Xcode (tools/ios_fix_xcode.py :
## CADisableMinimumFrameDurationOnPhone + affichage à la fréquence maximale de l'écran).
## Android : demande la fréquence voulue à la surface de rendu (Surface.setFrameRate, Android 11+),
## au mieux : si l'appareil refuse, le jeu tourne à la fréquence que le système lui accorde.

const SETTING := &"frame_rate"
const MODE_MAX := "max"
const MODE_60 := "60"
const MODE_ECO := "eco"
const MODES: Array[String] = [MODE_MAX, MODE_60, MODE_ECO]

## Dernière fréquence demandée à Android (évite de répéter l'appel).
static var _android_requested: float = -1.0


static func cap() -> int:
	return maxi(int(Balance.get_value("display", "max_fps_cap", 120)), 30)


static func eco_fps() -> int:
	return maxi(int(Balance.get_value("display", "eco_fps", 30)), 15)


## Fréquence de l'écran (Hz), 60 si inconnue.
static func screen_refresh() -> float:
	var r := DisplayServer.screen_get_refresh_rate()
	return r if r > 1.0 else 60.0


## Images par seconde visées pour un mode.
static func target_for(mode: String, refresh: float = -1.0) -> int:
	var hz := refresh if refresh > 0.0 else screen_refresh()
	match mode:
		MODE_ECO:
			return eco_fps()
		MODE_60:
			return 60
	# « max » : fréquence de l'écran arrondie (59,94 → 60 ; 119,88 → 120), plafonnée, au moins 60.
	return clampi(roundi(hz), 60, cap())


## L'écran permet-il plus de 60 i/s ?
static func high_refresh_available() -> bool:
	return target_for(MODE_MAX) > 60


## Mode enregistré (reprend l'ancien réglage « Économie d'énergie »).
static func saved_mode() -> String:
	var m := String(MenuKit.get_setting(SETTING, ""))
	if MODES.has(m):
		return m
	if bool(MenuKit.get_setting(&"power_saving", false)):
		return MODE_ECO
	return String(Balance.get_value("display", "default_frame_rate", MODE_MAX))


## Applique un mode (et l'enregistre si `persist`). Renvoie les images par seconde visées.
static func apply(mode: String, persist: bool = false) -> int:
	if not MODES.has(mode):
		mode = MODE_MAX
	if persist:
		MenuKit.set_setting(SETTING, mode)
		MenuKit.set_setting(&"power_saving", mode == MODE_ECO)
	var fps := target_for(mode)
	Engine.max_fps = fps
	_request_android(float(fps))
	return fps


## Mode suivant (bouton des Options : max → 60 → éco → max).
static func next_mode(mode: String) -> String:
	var i := MODES.find(mode)
	return MODES[(i + 1) % MODES.size()] if i >= 0 else MODE_MAX


## Libellé du bouton des Options.
static func label_for(mode: String) -> String:
	match mode:
		MODE_ECO:
			return "%d i/s · éco" % eco_fps()
		MODE_60:
			return "60 i/s"
	return "Max · %d i/s" % target_for(MODE_MAX)


## Android : Surface.setFrameRate(fps, compatibilité par défaut) sur la vue de rendu de Godot.
static func _request_android(fps: float) -> void:
	if OS.get_name() != "Android" or is_equal_approx(fps, _android_requested):
		return
	if not Engine.has_singleton("AndroidRuntime"):
		return
	_android_requested = fps
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Object = rt.call("getActivity") if rt.has_method("getActivity") else null
	if activity == null or not activity.has_method("getGodot"):
		return
	var godot: Object = activity.call("getGodot")
	if godot == null or not godot.has_method("getRenderView"):
		return
	var view: Object = godot.call("getRenderView")
	if view != null and view.has_method("getView"):
		view = view.call("getView")
	if view == null or not view.has_method("getHolder"):
		return
	var holder: Object = view.call("getHolder")
	var surface: Object = holder.call("getSurface") if holder != null and holder.has_method("getSurface") else null
	if surface != null and surface.has_method("setFrameRate"):
		surface.call("setFrameRate", fps, 0)
