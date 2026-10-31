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


class Notifier extends RefCounted:
	signal changed(on: bool)


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


## Tests : oublie la bascule et le contrôle injecté (relecture du réglage par défaut).
static func reset() -> void:
	var before := is_unlimited()
	build_check = Callable()
	_unlimited = null
	if is_unlimited() != before:
		notifier.changed.emit(is_unlimited())


static func _default_from_balance() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var bal: Node = ml.root.get_node_or_null(^"Balance") if ml != null else null
	return bool(bal.call("get_value", "dev", "unlimited_currency", false)) if bal != null else false
