class_name NetHooks
extends RefCounted
## Points de branchement du coop dans le code de jeu (raid.gd, player.gd, enemy.gd,
## scripts/combat/*, scripts/loot/*). Chaque crochet est une ligne du type
##   if NetHooks.active: NetHooks.on_xxx(...)
## En solo, `active` est faux : coût = un test de booléen statique, rien d'autre.
## Toute la logique est dans CoopRaid (scripts/net/coop_raid.gd).

const GROUP_AVATAR := &"coop_avatar"

## Raid coop en cours (CoopRaid attaché).
static var active: bool = false
static var is_host: bool = false
## Invité : les dégâts locaux sont désactivés (l'hôte fait autorité).
static var guest_mode: bool = false
## Vrai pendant l'application d'un message distant (évite les échos et laisse passer les
## dégâts envoyés par l'hôte).
static var applying_remote: bool = false
static var coop: CoopRaid = null
## Joueurs ciblables par les ennemis (hôte : joueur local + avatar de l'invité).
static var targets: Array[Node2D] = []


## Appelé par Raid._ready : attache CoopRaid si un raid coop a été lancé depuis le salon.
static func attach_raid(raid: Node) -> void:
	var s := NetSession.current()
	if s == null or not s.raid_pending or not s.in_room():
		return
	s.raid_pending = false
	var c := CoopRaid.new()
	c.name = "Coop"
	c.setup(raid as Raid, s)
	raid.add_child(c)


static func reset() -> void:
	active = false
	is_host = false
	guest_mode = false
	applying_remote = false
	coop = null
	targets.clear()


## Joueur visé par un ennemi : le plus proche des joueurs ciblables (vivant, pas à terre, pas
## extrait), avec une préférence pour la cible actuelle (pas de va-et-vient).
static func enemy_target(e: Node2D, cached: Node2D) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for t: Node2D in targets:
		if not is_targetable(t):
			continue
		var d := e.global_position.distance_squared_to(t.global_position)
		if t == cached:
			d *= 0.6
		if d < best_d:
			best_d = d
			best = t
	return best


static func is_targetable(t: Node2D) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree() or not t.visible:
		return false
	if t.has_meta(&"coop_gone"):
		return false
	var p := t as Player
	if p != null:
		return p.is_alive() and not p.net_downed
	return true


## Un joueur à terre ?
static func is_downed(p: Node) -> bool:
	return p is Player and (p as Player).net_downed


## Invité : les dégâts calculés localement sont ignorés (seuls ceux de l'hôte comptent).
static func blocks_local_damage() -> bool:
	return guest_mode and not applying_remote


## Joueur local à 0 PV : true si le coop le met « à terre » au lieu de le tuer.
static func player_down(p: Node) -> bool:
	return coop != null and coop.on_local_lethal(p as Player)


## Projectile de joueur tiré (ProjectilePool.spawn).
static func on_player_projectile(p: Node2D, pos: Vector2, dir: Vector2, weapon: WeaponData, source: Node, height: float) -> void:
	if coop != null and not applying_remote:
		coop.on_player_projectile(p, pos, dir, weapon, source, height)


## Projectile ennemi tiré (EnemyProjectilePool.spawn).
static func on_enemy_projectile(pos: Vector2, dir: Vector2, speed: float, life: float, style: StringName) -> void:
	if coop != null and is_host and not applying_remote:
		coop.on_enemy_projectile(pos, dir, speed, life, style)


## Appel visuel d'un ennemi (Enemy._visual_call) : relayé à l'invité.
static func on_enemy_visual(e: Node2D, method: StringName, args: Array) -> void:
	if coop != null and is_host and not applying_remote:
		coop.on_enemy_visual(e, method, args)


static func on_enemy_dynamite(from: Vector2, to: Vector2, radius: float, flight: float, fuse: float) -> void:
	if coop != null and is_host and not applying_remote:
		coop.on_enemy_dynamite(from, to, radius, flight, fuse)


## Ennemi créé en cours de raid (renforts appelés par un chef) : identité réseau.
## Hôte : `id` < 0 → un identifiant est attribué et renvoyé. Invité : `id` = celui de l'hôte,
## l'ennemi devient une marionnette. Hors coop : -1.
static func register_dynamic_enemy(e: Node2D, id: int = -1) -> int:
	if coop == null:
		return -1
	return coop.register_dynamic_enemy(e, id)


## Invité : retour visuel d'un impact (pas de dégâts locaux).
static func guest_hit_feedback(other: Node) -> void:
	if other is Enemy:
		(other as Enemy)._visual_call(&"play_hit")


static func on_door_changed(door: Variant) -> void:
	if coop != null and not applying_remote and door is Node2D:
		coop.on_door_changed(door as Node2D)


## Raid._on_stairs_entered : true = le coop gère (compte à rebours commun).
static func intercept_stairs(stairs: Variant) -> bool:
	return coop != null and coop.intercept_stairs(stairs)


## Raid._show_end_screen : true = le coop gère (spectateur puis écran de fin).
static func defer_end_screen(success: bool, summary: Dictionary) -> bool:
	return coop != null and coop.defer_end_screen(success, summary)


static func note_abandon() -> void:
	if coop != null:
		coop.abandoned = true


## Point de vue du brouillard (spectateur : le coéquipier).
static func view_position(default: Vector2) -> Vector2:
	return coop.view_position(default) if coop != null else default


## Conteneur : ce joueur peut-il fouiller / ouvrir ? (un seul joueur à la fois)
static func container_can_use(c: Node2D) -> bool:
	return coop == null or applying_remote or coop.container_request(c)


static func container_opened(c: Node2D) -> void:
	if coop != null and not applying_remote:
		coop.container_opened(c)


static func container_taken(c: Node2D, item_id: StringName, count: int) -> void:
	if coop != null and not applying_remote:
		coop.container_taken(c, item_id, count)


## Équipement utilisé par le joueur local (op : &"throw", &"drone", &"c4_detonate").
static func on_gadget(p: Node2D, w: WeaponData, op: StringName, from: Vector2, target: Vector2, height: float) -> void:
	if coop != null and not applying_remote:
		coop.on_gadget(p, w, op, from, target, height)
