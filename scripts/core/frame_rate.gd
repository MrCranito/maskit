class_name FrameRate
extends RefCounted
## Images par seconde du jeu (réglage « Images par seconde » des Options).
##  - « max » (par défaut sur ordinateur) : la fréquence de l'écran, plafonnée à [display] max_fps_cap
##    (120) — 120 i/s sur les téléphones à écran 120 Hz (iPhone Pro ProMotion, Android 120 Hz), 60 sinon ;
##  - « 60 » (par défaut sur mobile, [display] default_frame_rate_mobile) : 60 i/s. Sur un écran
##    120 Hz, viser 120 i/s double le travail du GPU (chauffe, bridage) et une image > 8,3 ms rate
##    une synchro : le rythme alterne 8 / 16 ms (saccades). 120 reste disponible dans les Options ;
##  - « eco » : économie d'énergie, [display] eco_fps (30) i/s (moins de chauffe et de batterie).
## La logique du jeu reste à 60 pas de physique par seconde : l'interpolation physique
## (physics/common/physics_interpolation) rend les déplacements fluides à 120 i/s.
## iOS : l'écran 120 Hz est déverrouillé dans le projet Xcode (tools/ios_fix_xcode.py :
## CADisableMinimumFrameDurationOnPhone + affichage à la fréquence maximale de l'écran).
## Limiteur : quand la synchro verticale est active et que la cible atteint la fréquence de
## l'écran, Engine.max_fps vaut 0 (la synchro seule cadence les images). Un limiteur logiciel
## égal à la fréquence de l'écran se bat avec la synchro et provoque des micro-saccades.
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
	return default_mode()


## Mode par défaut (sans réglage enregistré) : [display] default_frame_rate_mobile sur mobile
## (Android, iOS), [display] default_frame_rate ailleurs.
static func default_mode(mobile: Variant = null) -> String:
	var is_mobile: bool = OS.has_feature("mobile") if mobile == null else bool(mobile)
	var key := "default_frame_rate_mobile" if is_mobile else "default_frame_rate"
	var m := String(Balance.get_value("display", key, MODE_60 if is_mobile else MODE_MAX))
	return m if MODES.has(m) else MODE_MAX


## Valeur d'Engine.max_fps pour viser `fps` : 0 (synchro seule) si la synchro verticale est
## active et que la cible atteint la fréquence de l'écran, sinon `fps`.
static func engine_limit(fps: int, refresh: float = -1.0, vsync: Variant = null) -> int:
	var hz := refresh if refresh > 0.0 else screen_refresh()
	var vs: bool = (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED) if vsync == null else bool(vsync)
	if vs and fps >= roundi(hz):
		return 0
	return fps


## Applique un mode (et l'enregistre si `persist`). Renvoie les images par seconde visées.
static func apply(mode: String, persist: bool = false) -> int:
	if not MODES.has(mode):
		mode = MODE_MAX
	if persist:
		MenuKit.set_setting(SETTING, mode)
		MenuKit.set_setting(&"power_saving", mode == MODE_ECO)
	var fps := target_for(mode)
	Engine.max_fps = engine_limit(fps)
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
