class_name DevMode
extends RefCounted
## Mode développeur « ressources illimitées » : gemmes et or illimités pour tester la boutique,
## l'armurerie, l'artisanat et le pass sans rien payer. Statique (pas d'autoload).
##
## Sécurité : JAMAIS disponible dans une version publiée. is_available() exige un build debug
## (OS.is_debug_build()), l'éditeur (OS.has_feature("editor")) ou l'APK de test (feature tag
## « dev_apk », ajouté par .github/workflows/android.yml à son export release, jamais par
## export.yml) ; sinon is_unlimited() vaut
## toujours false, quel que soit le réglage. Le contrôle est injectable (`build_check`) pour les tests.
##
## Le mode ne touche jamais au solde réel : Profile.debit() ne débite rien tant qu'il est actif,
## Profile.balance_of() renvoie UNLIMITED et les compteurs affichent « ∞ ». Le désactiver rend
## le vrai solde (inchangé, et seul sauvegardé). Réglage par défaut : balance.cfg [dev] unlimited_currency.
## Bascule : panneau F3 (DevPanel) ou F4 quand le debug F3 est ouvert. Non persisté.
##
## « Tout débloquer » (is_all_unlocked) : profil de développement VIRTUEL (DevTools.build_profile) :
## toutes les armes (exemplaires à affixes compris), tous les objets en quantité, tous les skins, pass
## de combat complet (premium compris), niveau de raider maximal (cartes et emplacements), toute la
## rotation de cartes ouverte. Profile et BattlePass basculent en mémoire sur ce profil et n'écrivent
## plus rien dans SaveManager : la vraie sauvegarde (et donc la synchro cloud) n'en voit jamais rien.
## Désactivé : on recharge exactement le profil réel depuis SaveManager. Refusé pendant un raid.
## Non persisté (comme l'argent illimité).

## Solde « affiché / dépensable » en mode illimité (assez grand pour tout acheter, tient dans un int).
const UNLIMITED := 999_999_999
## Texte des compteurs en mode illimité.
const SYMBOL := "∞"

## Contrôle « build de développement » injectable (tests) : Callable() -> bool. Vide = vrai contrôle.
static var build_check: Callable = Callable()
## Prévient des bascules (signal `changed(on)`) : Profile, DevPanel, compteurs.
static var notifier: Notifier = Notifier.new()
## null tant que le réglage par défaut (balance.cfg) n'a pas été lu.
static var _unlimited: Variant = null
## « Tout débloquer » demandé (n'a d'effet que si is_available()).
static var _all_unlocked: bool = false


class Notifier extends RefCounted:
	signal changed(on: bool)
	## « Tout débloquer » basculé (Profile et BattlePass changent de profil).
	signal unlock_changed(on: bool)


## Le mode peut-il exister dans ce build ? (debug ou éditeur ; jamais en version publiée)
static func is_available() -> bool:
	if build_check.is_valid():
		return bool(build_check.call())
	return OS.is_debug_build() or OS.has_feature("editor") or OS.has_feature("dev_apk")


## Gemmes et or illimités en ce moment ? Toujours false hors build de développement.
static func is_unlimited() -> bool:
	if not is_available():
		return false
	if _unlimited == null:
		_unlimited = _default_from_balance()
	return bool(_unlimited)


## Active / désactive le mode. Refusé (false) hors build de développement. Renvoie l'état obtenu.
static func set_unlimited(on: bool) -> bool:
	if on and not is_available():
		return false
	var before := is_unlimited()
	_unlimited = on
	var now := is_unlimited()
	if now != before:
		notifier.changed.emit(now)
	return now


static func toggle() -> bool:
	return set_unlimited(not is_unlimited())


## « Tout débloquer » actif ? Toujours false hors build de développement.
static func is_all_unlocked() -> bool:
	return _all_unlocked and is_available()


## Active / désactive « Tout débloquer ». Refusé hors build de développement et pendant un raid
## (on ne change pas de profil avec des armes en jeu). Renvoie l'état obtenu.
static func set_all_unlocked(on: bool) -> bool:
	if on and not is_available():
		return false
	if on == is_all_unlocked():
		return on
	if _raid_in_progress():
		return is_all_unlocked()
	_all_unlocked = on
	notifier.unlock_changed.emit(is_all_unlocked())
	return is_all_unlocked()


static func toggle_all_unlocked() -> bool:
	return set_all_unlocked(not is_all_unlocked())


static func _raid_in_progress() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var p: Node = ml.root.get_node_or_null(^"Profile") if ml != null else null
	return p != null and bool(p.get("raid_in_progress"))


## Tests : oublie la bascule et le contrôle injecté (relecture du réglage par défaut).
static func reset() -> void:
	if is_all_unlocked():
		_all_unlocked = false
		notifier.unlock_changed.emit(false)
	_all_unlocked = false
	var before := is_unlimited()
	build_check = Callable()
	_unlimited = null
	if is_unlimited() != before:
		notifier.changed.emit(is_unlimited())


static func _default_from_balance() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var bal: Node = ml.root.get_node_or_null(^"Balance") if ml != null else null
	return bool(bal.call("get_value", "dev", "unlimited_currency", false)) if bal != null else false
