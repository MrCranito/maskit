class_name OnlineMode
extends RefCounted
## Mode de jeu choisi par le joueur au lobby (interrupteur « En ligne / Hors ligne » sous DÉPLOYER).
##   - En ligne (défaut) : comportement normal (sauvegarde cloud, coop par le relais).
##   - Hors ligne : partie solo sans réseau. CloudSync ne tente plus rien (ni connexion ni envoi :
##     les modifications restent marquées « à pousser » et partent au retour en ligne), le salon
##     coop est inaccessible (« + Coéquipier » grisé).
## Mémorisé dans les réglages du profil (SaveManager.data["settings"]["online"], via MenuKit).
## Statique (pas d'autoload) ; `notifier.changed(online)` prévient CloudSync et le lobby.

const SETTING := &"online"

static var notifier: Notifier = Notifier.new()


class Notifier extends RefCounted:
	signal changed(online: bool)


static func is_online() -> bool:
	return bool(MenuKit.get_setting(SETTING, true))


## Change le mode (persisté). Renvoie le mode obtenu.
static func set_online(on: bool) -> bool:
	if on == is_online():
		return on
	MenuKit.set_setting(SETTING, on)
	notifier.changed.emit(on)
	return on
