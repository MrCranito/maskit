class_name EnemySkills
extends RefCounted
## Registre des compétences ennemies (id → classe dans scripts/enemies/skills/) et outils
## communs : cibles (joueur, coéquipier en coop), dégâts et statuts appliqués aux joueurs,
## renforts. Réglages globaux : balance.cfg [enemy_skills].

const DIR := "res://scripts/enemies/skills/"
## id → fichier (une classe par famille de compétence ; certains ids partagent une classe et
## ne diffèrent que par leurs paramètres).
const REGISTRY := {
	# Far West
	&"dodge_roll": "dodge_skill.gd",
	&"cover_roll": "dodge_skill.gd",
	&"knife_throw": "projectile_skill.gd",
	&"fan_volley": "projectile_skill.gd",
	&"charge": "charge_skill.gd",
	&"rush": "charge_skill.gd",
	&"hard_skin": "guard_skill.gd",
	&"shield": "guard_skill.gd",
	&"energy_shield": "guard_skill.gd",
	&"relocate": "relocate_skill.gd",
	&"piercing": "piercing_skill.gd",
	&"molotov": "throw_skill.gd",
	&"bounce_dynamite": "throw_skill.gd",
	&"grenade": "throw_skill.gd",
	&"flash_grenade": "throw_skill.gd",
	&"whistle": "whistle_skill.gd",
	&"rage": "rage_skill.gd",
	# Station spatiale
	&"teleport": "teleport_skill.gd",
	&"kamikaze": "kamikaze_skill.gd",
	&"deploy_turret": "deploy_skill.gd",
	&"shockwave": "shockwave_skill.gd",
}

## Registres par monde (bestiaire) : scripts/enemies/skills/<monde>/registry.gd, chacun avec
## `const REGISTRY := {&"id": "res://chemin/complet.gd"}` (chemins complets). Un fichier par monde :
## chaque monde ajoute ses compétences sans toucher à ce fichier.
const WORLD_REGISTRIES: Array[String] = [
	"res://scripts/enemies/skills/far_west/registry.gd",
	"res://scripts/enemies/skills/space_station/registry.gd",
	"res://scripts/enemies/skills/mall/registry.gd",
]

static var _scripts: Dictionary = {}
static var _merged: Dictionary = {}
static var _merged_ok: bool = false


## id → chemin complet du script (registre commun + registres des mondes).
static func registry() -> Dictionary:
	if _merged_ok:
		return _merged
	_merged_ok = true
	_merged.clear()
	for k: Variant in REGISTRY:
		_merged[k] = DIR + String(REGISTRY[k])
	for rp: String in WORLD_REGISTRIES:
		if not ResourceLoader.exists(rp):
			continue
		var scr := load(rp) as Script
		if scr == null:
			continue
		var reg: Variant = scr.get_script_constant_map().get("REGISTRY", {})
		if reg is Dictionary:
			for k2: Variant in reg:
				_merged[StringName(str(k2))] = String(reg[k2])
	return _merged


static func has_skill(id: StringName) -> bool:
	return registry().has(id)


## Instancie les compétences déclarées par `data.skills` (ids inconnus ignorés avec un avertissement).
static func build(e: Enemy, data: EnemyData) -> Array[EnemySkill]:
	var out: Array[EnemySkill] = []
	if data == null:
		return out
	for entry: Variant in data.skills:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var sid := StringName(str(d.get("id", "")))
		var s := create(sid)
		if s == null:
			push_warning("EnemySkills : compétence inconnue « %s » (%s)." % [sid, data.kind])
			continue
		s.id = sid
		s.setup(e, d)
		out.append(s)
	return out


static func create(sid: StringName) -> EnemySkill:
	var reg := registry()
	if not reg.has(sid):
		return null
	var path: String = String(reg[sid])
	var scr: Script = _scripts.get(path) as Script
	if scr == null:
		scr = load(path) as Script
		_scripts[path] = scr
	if scr == null:
		return null
	var s := scr.new() as EnemySkill
	if s != null:
		s.id = sid
	return s


# --- Cibles et effets ----------------------------------------------------------------

## Le nœud est-il un joueur (local ou coéquipier côté hôte) ?
static func is_player_target(n: Node) -> bool:
	return n != null and (n.is_in_group(&"player") or n.is_in_group(&"coop_avatar"))


## Joueurs touchables (vivants) : en coop, les cibles de NetHooks ; sinon le groupe player.
static func player_targets(tree: SceneTree, out: Array[Node2D]) -> void:
	out.clear()
	if NetHooks.active:
		for t: Node2D in NetHooks.targets:
			if NetHooks.is_targetable(t):
				out.append(t)
		return
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group(&"player"):
		var p := n as Node2D
		if p != null and (not p.has_method("is_alive") or bool(p.call("is_alive"))):
			out.append(p)


static var _targets_buf: Array[Node2D] = []


## Dégâts + statut aux joueurs dans le disque (centre, rayon). Renvoie le nombre touché.
## `real` faux (invité en coop) : rien n'est appliqué (l'hôte fait autorité).
static func hit_players_in_radius(tree: SceneTree, center: Vector2, radius: float, damage: float, source: Node,
		status: StringName = &"", status_time: float = 0.0, strength: float = 1.0, real: bool = true) -> int:
	if not real:
		return 0
	player_targets(tree, _targets_buf)
	var n := 0
	for p: Node2D in _targets_buf:
		if p.global_position.distance_to(center) > radius:
			continue
		hit_player(p, damage, source, status, status_time, strength, center)
		n += 1
	return n


## Dégâts + statut à un joueur.
static func hit_player(p: Node2D, damage: float, source: Node, status: StringName = &"",
		status_time: float = 0.0, strength: float = 1.0, from: Vector2 = Vector2.INF) -> void:
	if p == null or not is_instance_valid(p):
		return
	if damage > 0.0 and p.has_method("take_damage"):
		p.call("take_damage", damage, source if is_instance_valid(source) else null)
	if status != &"" and status_time > 0.0 and p.has_method("apply_status"):
		p.call("apply_status", status, status_time, strength, from)


static func cfg(key: String, def: float) -> float:
	return Balance.get_float("enemy_skills", key, def)
