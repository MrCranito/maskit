class_name CoopRules
extends RefCounted
## Règles du coop (logique pure, testable) : à terre / réanimation, fin de raid de chaque
## joueur, déconnexions. Valeurs dans balance.cfg [net].
##
## Décisions de design (documentées dans server/README.md) :
##  - PV : un joueur à 0 PV passe « à terre » `downed_time` s si son coéquipier est encore en
##    raid (vivant, connecté) ; sinon il meurt directement. Le coéquipier le réanime en
##    maintenant l'action `revive_time` s à moins de `revive_range` px ; la réanimation en cours
##    suspend le compte à rebours. Réanimé : `revive_hp_ratio` × PV max.
##  - Mort ou extraction : individuelles. Celui qui finit avant regarde son coéquipier
##    (spectateur) ; chacun met à jour SON Profile avec SON butin.
##  - Invité déconnecté plus de `guest_timeout` s : considéré comme mort (arsenal et butin perdus).
##  - Hôte déconnecté (salon fermé) : fin du raid pour l'invité, qui GARDE son arsenal emporté
##    mais PERD le butin du raid (il n'est pas responsable de la coupure, mais ne peut pas
##    sortir le butin d'une partie que plus personne ne simule).

enum Status { ALIVE, DOWNED, DEAD, EXTRACTED, LEFT, DISCONNECTED }

const STATUS_TEXT := {
	Status.ALIVE: "En vie",
	Status.DOWNED: "À terre",
	Status.DEAD: "Mort",
	Status.EXTRACTED: "Extrait",
	Status.LEFT: "Parti",
	Status.DISCONNECTED: "Connexion perdue",
}


static func status_text(s: int) -> String:
	return String(STATUS_TEXT.get(s, "?"))


static func downed_time() -> float:
	return maxf(Balance.get_float("net", "downed_time", 15.0), 1.0)


static func revive_time() -> float:
	return maxf(Balance.get_float("net", "revive_time", 3.0), 0.2)


static func revive_range() -> float:
	return Balance.get_float("net", "revive_range", 90.0)


static func revive_hp_ratio() -> float:
	return clampf(Balance.get_float("net", "revive_hp_ratio", 0.35), 0.05, 1.0)


## Le coéquipier est-il encore dans le raid (peut réanimer, peut être regardé) ?
static func in_raid(s: int) -> bool:
	return s == Status.ALIVE or s == Status.DOWNED


## À 0 PV : à terre (true) ou mort directe (false) ?
static func should_go_down(partner_status: int, partner_connected: bool) -> bool:
	return partner_connected and partner_status == Status.ALIVE


## Compte à rebours « à terre » : renvoie le temps restant après `delta`. Suspendu pendant une
## réanimation en cours.
static func step_downed(left: float, delta: float, being_revived: bool) -> float:
	if being_revived:
		return left
	return maxf(left - delta, 0.0)


## Progression d'une réanimation (0..1) après `delta`, ou -1 si interrompue (trop loin,
## réanimateur à terre, cible plus à terre).
static func step_revive(progress: float, delta: float, distance: float, reviver_ok: bool, target_downed: bool) -> float:
	if not reviver_ok or not target_downed or distance > revive_range():
		return -1.0
	return minf(progress + delta / revive_time(), 1.0)


## Ma fin de raid est faite : faut-il passer spectateur (sinon : écran de fin tout de suite) ?
static func should_spectate(partner_status: int, partner_connected: bool, abandoned: bool) -> bool:
	return not abandoned and partner_connected and in_raid(partner_status)


## Issue pour l'invité quand le salon se ferme ou que la connexion est perdue.
##  reason : "host_left", "host_timeout", "expired" (hôte responsable) → &"keep_arsenal" ;
##           "kicked_timeout", "bad_token", "unreachable" (invité absent trop longtemps) → &"death".
static func guest_outcome(reason: String) -> StringName:
	match reason:
		"host_left", "host_timeout", "expired", "not_found":
			return &"keep_arsenal"
	return &"death"


## Fin de raid de l'invité quand l'hôte a disparu : l'arsenal emporté revient dans la réserve,
## le butin du raid est perdu. Utilise uniquement l'API publique du Profile.
## Renvoie un résumé {kept_weapons, lost_items, lost_value}.
static func apply_host_lost(profile: Node, bag: Inventory) -> Dictionary:
	var kept: Array[StringName] = []
	var lost_items := 0
	var lost_value := 0
	if bag != null:
		for i: int in bag.capacity():
			var sl := bag.get_slot(i)
			if not sl.is_empty():
				lost_items += int(sl.get("count", 1))
		lost_value = bag.total_value()
	if profile == null:
		return {"kept_weapons": kept, "lost_items": lost_items, "lost_value": lost_value}
	var ids: Variant = profile.get("raid_weapon_ids")
	if ids is Array:
		for id: Variant in (ids as Array).duplicate():
			if int(profile.call("add_weapon", StringName(str(id)))) > 0:
				kept.append(StringName(str(id)))
		(ids as Array).clear()
	profile.set("raid_in_progress", false)
	if profile.has_method("ensure_starter"):
		profile.call("ensure_starter")
	if profile.has_method("save"):
		profile.call("save")
	return {"kept_weapons": kept, "lost_items": lost_items, "lost_value": lost_value}


## PV ennemis en coop (barème à 2 joueurs, voir party_mult).
static func coop_hp_mult() -> float:
	return party_mult("enemy_hp", 2)


# --- Difficulté selon le nombre de joueurs --------------------------------------------

## Nombre de joueurs maximal prévu par le barème (le jeu en permet 2 aujourd'hui).
const MAX_PARTY := 4
## Tests : force le nombre de joueurs du prochain raid (0 = automatique).
static var party_override: int = 0


## Multiplicateur du barème [coop] <key>_<n> (enemy_density, enemy_hp, enemy_damage) pour
## `players` joueurs (1..4). Solo : toujours 1 (aucun changement). Repli à 2 joueurs sur
## l'ancien réglage [net] coop_enemy_hp_mult pour les PV.
static func party_mult(key: String, players: int) -> float:
	var n := clampi(players, 1, MAX_PARTY)
	if n <= 1:
		return 1.0
	var fallback := 1.0
	if key == "enemy_hp":
		fallback = Balance.get_float("net", "coop_enemy_hp_mult", 1.6)
	return maxf(Balance.get_float("coop", "%s_%d" % [key, n], fallback), 0.05)


## Joueurs du raid qui démarre (lu par Raid._ready AVANT la génération, identique chez l'hôte
## et l'invité : la seed et ce nombre suffisent à générer le même étage des deux côtés).
## Salon coop : raid_info["players"] posé au lancement (2 par défaut) ; solo : 1.
static func raid_party_size() -> int:
	if party_override > 0:
		return clampi(party_override, 1, MAX_PARTY)
	var s := NetSession.current()
	if s != null and s.raid_pending and s.in_room():
		return clampi(int(s.raid_info.get("players", 2)), 1, MAX_PARTY)
	return 2 if NetHooks.active else 1
