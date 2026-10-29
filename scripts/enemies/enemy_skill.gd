class_name EnemySkill
extends RefCounted
## Compétence active (ou passive) d'un ennemi, déclarée dans son EnemyData :
##   skills = [{"id": &"knife_throw", "cooldown": 5.0, "windup": 0.45, ...}, ...]
## Les paramètres du .tres remplacent les valeurs par défaut de la classe (`defaults()`).
##
## Cycle d'une compétence active (exécutée par l'état « Skill » de l'IA, cf. enemy_skill_state.gd) :
##   conditions (recharge, distance [min_range, max_range], ligne de vue, PV, alliés, hasard)
##   → begin() : TÉLÉGRAPHE (visuel relayé au coéquipier en coop) pendant `windup` s
##   → update(dt) jusqu'à la fin de l'exécution → recharge `cooldown` s.
## Une compétence passive (`passive = true`) n'est jamais exécutée par l'état Skill : elle agit par
## ses crochets (modify_damage, on_damaged, on_attack_done, on_fire).
## Les compétences « réactives » (`reactive = true`, ex. roulade quand on le vise) sont testées
## plus souvent (Enemy._skill_tick), toujours sans allocation par image.

var id: StringName = &""
var e: Enemy = null
var p: Dictionary = {}
var cooldown_left: float = 0.0
## Vrai entre begin() et la fin de l'exécution.
var running: bool = false
## Temps écoulé depuis begin().
var t: float = 0.0
## Nombre d'utilisations (tests, debug F3).
var uses: int = 0


## Valeurs par défaut communes (surchargées par chaque compétence puis par le .tres).
func base_defaults() -> Dictionary:
	return {
		"cooldown": 8.0, "initial_cooldown": 2.0, "windup": 0.6, "min_range": 0.0, "max_range": 9999.0,
		"need_los": true, "hp_below": 1.01, "hp_above": 0.0, "chance": 1.0, "priority": 1.0,
		"passive": false, "reactive": false,
	}


## Valeurs propres à la compétence (à surcharger).
func defaults() -> Dictionary:
	return {}


func setup(enemy: Enemy, params: Dictionary) -> void:
	e = enemy
	p = base_defaults()
	p.merge(defaults(), true)
	p.merge(params, true)
	id = StringName(str(p.get("id", id)))
	cooldown_left = randf_range(0.5, 1.0) * float(p["initial_cooldown"])


func f(key: String) -> float:
	return float(p.get(key, 0.0))


func b(key: String) -> bool:
	return bool(p.get(key, false))


func is_passive() -> bool:
	return b("passive")


func is_reactive() -> bool:
	return b("reactive")


func tick_cooldown(dt: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= dt


## Conditions communes + conditions propres (can_use_extra).
func can_use(dist: float, sees: bool) -> bool:
	if is_passive() or running or cooldown_left > 0.0 or e == null:
		return false
	if dist < f("min_range") or dist > f("max_range"):
		return false
	if b("need_los") and not sees:
		return false
	var ratio := e.hp / maxf(e.max_hp, 0.01)
	if ratio > f("hp_below") or ratio < f("hp_above"):
		return false
	return can_use_extra(dist, sees)


## Conditions propres (à surcharger).
func can_use_extra(_dist: float, _sees: bool) -> bool:
	return true


## Lance la compétence (télégraphe). Le temps de recharge part dès maintenant.
func begin() -> void:
	running = true
	t = 0.0
	uses += 1
	cooldown_left = f("cooldown") * e.skill_cooldown_mult()
	start()


## Début propre (à surcharger) : télégraphe, préparation.
func start() -> void:
	pass


## Avance l'exécution ; renvoie vrai quand c'est fini.
func update(dt: float) -> bool:
	t += dt
	return step(dt)


## Exécution propre (à surcharger) ; vrai = terminé.
func step(_dt: float) -> bool:
	return true


## Fin (normale ou interrompue : étourdi, mort) : nettoyer les télégraphes / vitesses.
func finish() -> void:
	running = false
	cleanup()


func cleanup() -> void:
	pass


## Durée de télégraphe effective (difficulté).
func windup() -> float:
	return f("windup") * e.diff_windup_mult


# --- Crochets passifs ------------------------------------------------------------------

## Dégâts reçus (avant application) : réduction, blocage. Renvoie les dégâts restants.
func modify_damage(amount: float, _source: Node) -> float:
	return amount


## Après des dégâts (PV déjà retirés).
func on_damaged(_amount: float) -> void:
	pass


## Fin d'une attaque de base (Attack → récupération).
func on_attack_done() -> void:
	pass


## Projectile de base tiré par l'ennemi (perforation…).
func on_fire(_projectile: Node) -> void:
	pass


# --- Outils --------------------------------------------------------------------------

func player() -> Node2D:
	return e.get_player()


func player_pos() -> Vector2:
	var pl := e.get_player()
	return pl.global_position if pl != null else e.last_seen_position


## Télégraphe / effet visuel relayé au coéquipier (EnemyVisual.play_skill_fx).
func fx(kind: StringName, a: Vector2 = Vector2.ZERO, b2: Vector2 = Vector2.ZERO, r: float = 0.0, dur: float = 0.0) -> void:
	e._visual_call(&"play_skill_fx", [kind, a, b2, r, dur])
