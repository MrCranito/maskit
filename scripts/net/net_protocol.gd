class_name NetProtocol
extends RefCounted
## Protocole de jeu du coop (données binaires relayées par le serveur, voir server/relay.js).
##
## Choix : protocole maison léger plutôt que MultiplayerPeerExtension + RPC/MultiplayerSynchronizer.
##  - Le raid est construit entièrement en code (étages reconstruits à chaque escalier, ennemis,
##    conteneurs, cadavres créés dynamiquement) : les chemins de nœuds ne sont pas stables d'un
##    pair à l'autre, ce qui casse RPC / MultiplayerSpawner. Les identités réseau sont ici
##    explicites et déterministes (index d'apparition de l'ennemi, case d'une porte ou d'une
##    tourelle, position d'un cadavre) grâce à la seed partagée.
##  - Contrôle total de la taille des paquets (positions quantifiées sur 16 bits, angles sur 8 ou
##    16 bits, PV sur 8 bits), du filtrage (seulement ce qui est proche du coéquipier) et de la
##    fréquence (état 20/s, ennemis 15/s, événements regroupés une fois par image).
##  - Aucun coût en solo : rien n'est créé tant qu'un salon n'est pas ouvert.
## Le transport est un WebSocket (TCP) : tout est fiable et ordonné ; l'état continu est
## simplement écrasé par le suivant.
##
## Paquet = suite de messages [u8 type][u16 longueur][charge utile]. Petit-boutiste.

## Version du protocole de transport (doit être égale à PROTOCOL_VERSION de server/relay.js).
const VERSION := 1
## Version des messages de jeu (vérifiée entre les deux joueurs dans le salon).
const GAME_VERSION := 2

enum Msg {
	STATE = 1,        ## état d'un joueur (20/s)
	LOADOUT = 2,      ## armes, skin, pseudo
	FIRE = 3,         ## projectile de joueur (invité → hôte : tir à valider ; hôte → invité : visuel)
	ENEMY_SNAP = 4,   ## positions/états des ennemis proches (hôte → invité, 15/s)
	ENEMY_FX = 5,     ## animation/télégraphe d'un ennemi (hôte → invité)
	ENEMY_DEATH = 6,  ## mort d'un ennemi
	ENEMY_SHOT = 7,   ## projectile ennemi (visuel chez l'invité)
	DAMAGE = 8,       ## dégâts subis par l'invité (hôte → invité)
	DOOR = 9,         ## porte ouverte / déverrouillée
	CONTAINER = 10,   ## verrou de fouille, ouverture, objet pris
	GROUND = 11,      ## butin au sol ramassé
	GADGET = 12,      ## grenade, mine, C4, fumée, drone
	PLAYER_EVT = 13,  ## à terre, réanimation, mort, extraction
	FLOOR = 14,       ## changement d'étage commun
	TURRET = 15,      ## tourelle détruite
	RAID_HELLO = 16,  ## le raid est chargé (seed de contrôle)
	DYNAMITE = 17,    ## dynamite lancée par un ennemi (visuel chez l'invité)
	STATUS = 18,      ## statut infligé à l'invité par une compétence ennemie (hôte → invité)
}

## Drapeaux de STATE.
const F_MOVING := 1
const F_AIMING := 2
const F_HIDDEN := 4
const F_DOWNED := 8
const F_DEAD := 16
const F_EXTRACTED := 32
const F_RELOADING := 64
const F_FIRED := 128

## Drapeaux de ENEMY_SNAP.
const EF_MOVING := 1
const EF_COMBAT := 2

## Opérations de PLAYER_EVT.
enum PlayerOp { DOWNED = 1, REVIVE_PROGRESS = 2, REVIVED = 3, DEAD = 4, EXTRACTED = 5, LEFT = 6 }
## Opérations de CONTAINER.
enum ContainerOp { LOCK = 1, UNLOCK = 2, DENY = 3, OPENED = 4, TAKEN = 5 }
## Opérations de FLOOR.
enum FloorOp { REQUEST = 1, COUNTDOWN = 2, GO = 3, CANCEL = 4 }
## Opérations de GADGET.
enum GadgetOp { THROW = 1, DRONE = 2, C4_DETONATE = 3 }
## Opérations de TURRET.
enum TurretOp { DESTROYED = 1 }

## Roster « tous les ennemis » dans FLOOR GO.
const ROSTER_ALL := 0xFFFF

## Méthodes visuelles d'ennemi relayées (ENEMY_FX), par index.
const FX_METHODS: Array[StringName] = [
	&"play_alert", &"play_attack_windup", &"show_aim_line", &"show_ground_marker", &"lock_aim_line",
	&"hide_telegraphs", &"play_strike", &"play_ground_slam", &"play_shout", &"play_stun",
	&"use_throw_anim", &"set_aim_direction", &"set_elite", &"play_hit",
	# Compétences ennemies (EnemySkills) : télégraphes/effets, dangers au sol, renforts.
	&"play_skill_fx", &"spawn_hazard", &"spawn_reinforcement",
]


# --- Quantification (logique pure) ----------------------------------------------------

## Position monde → entier 16 bits signé (1 px de précision, ±32767 px ≈ 512 cases).
static func q_pos(v: float) -> int:
	return clampi(roundi(v), -32768, 32767)


## Angle (rad) → 0..255.
static func q_angle8(a: float) -> int:
	return wrapi(roundi(a / TAU * 256.0), 0, 256)


static func dq_angle8(q: int) -> float:
	return float(q) / 256.0 * TAU


## Angle (rad) → 0..65535.
static func q_angle16(a: float) -> int:
	return wrapi(roundi(a / TAU * 65536.0), 0, 65536)


static func dq_angle16(q: int) -> float:
	return float(q) / 65536.0 * TAU


## Rapport 0..1 → 0..255.
static func q_ratio(r: float) -> int:
	return clampi(roundi(clampf(r, 0.0, 1.0) * 255.0), 0, 255)


static func dq_ratio(q: int) -> float:
	return float(q) / 255.0


## Vitesse (px/s) → 16 bits signé.
static func q_speed(v: float) -> int:
	return clampi(roundi(v), -32768, 32767)


## Horloge locale (ms) sur 32 bits.
static func now_ms() -> int:
	return Time.get_ticks_msec() & 0xFFFFFFFF


# --- Écriture -------------------------------------------------------------------------

## Tampon d'écriture réutilisé (aucune allocation hors copie finale du paquet).
class Writer extends RefCounted:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var _len_at: int = -1

	func clear() -> void:
		buf.clear()
		_len_at = -1

	func is_empty() -> bool:
		return buf.get_size() == 0

	func size() -> int:
		return buf.get_size()

	func begin(type: int) -> void:
		buf.put_u8(type)
		_len_at = buf.get_position()
		buf.put_u16(0)

	func end() -> void:
		if _len_at < 0:
			return
		var end_pos := buf.get_position()
		buf.seek(_len_at)
		buf.put_u16(end_pos - _len_at - 2)
		buf.seek(end_pos)
		_len_at = -1

	## Copie du paquet (à envoyer).
	func bytes() -> PackedByteArray:
		return buf.data_array.slice(0, buf.get_size())

	func u8(v: int) -> void:
		buf.put_u8(v & 0xFF)

	func i8(v: int) -> void:
		buf.put_8(clampi(v, -128, 127))

	func u16(v: int) -> void:
		buf.put_u16(v & 0xFFFF)

	func i16(v: int) -> void:
		buf.put_16(clampi(v, -32768, 32767))

	func u32(v: int) -> void:
		buf.put_u32(v & 0xFFFFFFFF)

	func f32(v: float) -> void:
		buf.put_float(v)

	func pos(v: Vector2) -> void:
		buf.put_16(NetProtocol.q_pos(v.x))
		buf.put_16(NetProtocol.q_pos(v.y))

	## Chaîne courte (≤ 255 octets UTF-8).
	func text(s: String) -> void:
		var b := s.to_utf8_buffer()
		if b.size() > 255:
			b = b.slice(0, 255)
		buf.put_u8(b.size())
		if b.size() > 0:
			buf.put_data(b)

	func blob(b: PackedByteArray) -> void:
		buf.put_u16(mini(b.size(), 0xFFFF))
		if b.size() > 0:
			buf.put_data(b.slice(0, mini(b.size(), 0xFFFF)))


# --- Lecture --------------------------------------------------------------------------

class Reader extends RefCounted:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	## Fin du message courant (position absolue).
	var msg_end: int = 0
	var ok: bool = true

	func reset(data: PackedByteArray) -> void:
		buf.data_array = data
		buf.seek(0)
		msg_end = 0
		ok = true

	## Message suivant : renvoie son type (0 = fin du paquet ou paquet tronqué).
	func next_msg() -> int:
		if msg_end > 0:
			buf.seek(mini(msg_end, buf.get_size()))
		if buf.get_size() - buf.get_position() < 3:
			return 0
		var t := buf.get_u8()
		var n := buf.get_u16()
		msg_end = buf.get_position() + n
		if msg_end > buf.get_size():
			ok = false
			return 0
		return t

	func remaining() -> int:
		return msg_end - buf.get_position()

	func _need(n: int) -> bool:
		if buf.get_position() + n > msg_end:
			ok = false
			return false
		return true

	func u8() -> int:
		return buf.get_u8() if _need(1) else 0

	func i8() -> int:
		return buf.get_8() if _need(1) else 0

	func u16() -> int:
		return buf.get_u16() if _need(2) else 0

	func i16() -> int:
		return buf.get_16() if _need(2) else 0

	func u32() -> int:
		return buf.get_u32() if _need(4) else 0

	func f32() -> float:
		return buf.get_float() if _need(4) else 0.0

	func pos() -> Vector2:
		if not _need(4):
			return Vector2.ZERO
		var x := buf.get_16()
		return Vector2(float(x), float(buf.get_16()))

	func text() -> String:
		var n := u8()
		if n == 0 or not _need(n):
			return ""
		var r: Array = buf.get_data(n)
		return (r[1] as PackedByteArray).get_string_from_utf8() if int(r[0]) == OK else ""

	func blob() -> PackedByteArray:
		var n := u16()
		if n == 0 or not _need(n):
			return PackedByteArray()
		var r: Array = buf.get_data(n)
		return r[1] if int(r[0]) == OK else PackedByteArray()


# --- État d'un joueur (STATE) ---------------------------------------------------------

## Échantillon d'état d'un joueur (réutilisé, pas d'allocation par paquet).
class PlayerState extends RefCounted:
	var time_ms: int = 0
	var floor_index: int = 0
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var aim: Vector2 = Vector2.RIGHT
	var flags: int = 0
	var hp_ratio: float = 1.0
	var slot: int = 0

	func has(flag: int) -> bool:
		return (flags & flag) != 0


static func write_state(w: Writer, s: PlayerState) -> void:
	w.begin(Msg.STATE)
	w.u32(s.time_ms)
	w.i8(s.floor_index)
	w.pos(s.position)
	w.i16(q_speed(s.velocity.x))
	w.i16(q_speed(s.velocity.y))
	w.u8(q_angle8(s.aim.angle()))
	w.u8(s.flags)
	w.u8(q_ratio(s.hp_ratio))
	w.u8(s.slot)
	w.end()


static func read_state(r: Reader, s: PlayerState) -> void:
	s.time_ms = r.u32()
	s.floor_index = r.i8()
	s.position = r.pos()
	var vx := r.i16()
	s.velocity = Vector2(float(vx), float(r.i16()))
	s.aim = Vector2.from_angle(dq_angle8(r.u8()))
	s.flags = r.u8()
	s.hp_ratio = dq_ratio(r.u8())
	s.slot = r.u8()


# --- Projectile de joueur (FIRE) --------------------------------------------------------

static func write_fire(w: Writer, weapon_id: String, origin: Vector2, dir: Vector2, height: float, homing: bool) -> void:
	w.begin(Msg.FIRE)
	w.text(weapon_id)
	w.pos(origin)
	w.u16(q_angle16(dir.angle()))
	w.u8(clampi(roundi(height), 0, 255))
	w.u8(1 if homing else 0)
	w.end()


## {weapon, origin, dir, height, homing} (lecture : les appelants lisent directement le Reader).
static func read_fire(r: Reader) -> Dictionary:
	var id := r.text()
	var o := r.pos()
	var d := Vector2.from_angle(dq_angle16(r.u16()))
	var h := float(r.u8())
	var hom := r.u8() != 0
	return {"weapon": id, "origin": o, "dir": d, "height": h, "homing": hom}


# --- Ennemis (ENEMY_SNAP) ---------------------------------------------------------------

## Écrit l'en-tête d'un instantané ; compléter par write_enemy() × n puis w.end().
static func begin_enemy_snap(w: Writer, time_ms: int, floor_index: int, count: int) -> void:
	w.begin(Msg.ENEMY_SNAP)
	w.u32(time_ms)
	w.i8(floor_index)
	w.u8(mini(count, 255))


static func write_enemy(w: Writer, id: int, p: Vector2, facing: Vector2, flags: int, hp_ratio: float, awareness: float) -> void:
	w.u16(id)
	w.pos(p)
	w.u8(q_angle8(facing.angle()))
	w.u8(flags)
	w.u8(q_ratio(hp_ratio))
	w.u8(q_ratio(awareness))


## Taille en octets d'un ennemi dans un instantané (budget réseau, tests).
const ENEMY_ENTRY_BYTES := 10
## Taille de la charge utile de STATE.
const STATE_BYTES := 17


# --- Divers ---------------------------------------------------------------------------

## Index d'une méthode visuelle relayée (-1 = non relayée).
static func fx_index(method: StringName) -> int:
	return FX_METHODS.find(method)


static func fx_method(index: int) -> StringName:
	return FX_METHODS[index] if index >= 0 and index < FX_METHODS.size() else &""


## Lobby : messages JSON relayés {k: ...}. Vérifie la compatibilité de version du pair.
static func compatible(peer_info: Dictionary) -> bool:
	return int(peer_info.get("gv", -1)) == GAME_VERSION
