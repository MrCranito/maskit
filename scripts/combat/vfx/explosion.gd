class_name Explosion
extends RefCounted
## Dégâts de zone (roquettes, grenades). Logique sans nœud propre :
##   - dégâts décroissants du centre (100 %) au bord (`min_frac`), rien au-delà du rayon ;
##   - cibles : nœuds du groupe `damageable` vivants (ennemis, tourelles, mannequins…) ;
##   - ligne de vue : UN raycast par cible dans le rayon, sur la couche world (bit 1),
##     murs et portes fermées bloquent l'explosion ;
##   - le joueur (groupe `player`) ne reçoit que `self_mult` × les dégâts (0 = immunisé).
##     Choix de design : [projectile_fx] explosion_self_damage_mult = 0.25 → tirer une
##     roquette à bout portant fait un peu mal, sans être punitif (et le joueur garde son
##     invulnérabilité après un coup).

const MASK_WORLD := 1


## Logique pure : dégâts à `dist` du centre (0 hors rayon), linéaire de `damage` au centre
## à `damage * min_frac` au bord.
static func falloff_damage(dist: float, radius: float, damage: float, min_frac: float = 0.25) -> float:
	if radius <= 0.0 or dist > radius or damage <= 0.0:
		return 0.0
	var t: float = clampf(dist / radius, 0.0, 1.0)
	return damage * lerpf(1.0, clampf(min_frac, 0.0, 1.0), t)


## Applique l'explosion. `space` peut être null (pas de test de ligne de vue).
## Renvoie la liste des cibles touchées (pour les numéros de dégâts et les tests).
## `out_amounts` reçoit les dégâts correspondants si fourni.
static func apply_damage(tree: SceneTree, space: PhysicsDirectSpaceState2D, center: Vector2,
		radius: float, damage: float, source: Node, min_frac: float = 0.25, self_mult: float = 0.25,
		out_amounts: Array = []) -> Array[Node2D]:
	var hit: Array[Node2D] = []
	if tree == null or radius <= 0.0 or damage <= 0.0:
		return hit
	if NetHooks.guest_mode and not NetHooks.applying_remote:
		return hit  # Coop, invité : explosion visuelle, dégâts calculés par l'hôte.
	var query: PhysicsRayQueryParameters2D = null
	if space != null:
		query = PhysicsRayQueryParameters2D.create(center, center, MASK_WORLD)
		query.collide_with_areas = false
		query.collide_with_bodies = true
	var r2: float = radius * radius
	for n: Node in tree.get_nodes_in_group(&"damageable"):
		var t := n as Node2D
		if t == null or not n.has_method("take_damage"):
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		var d2: float = center.distance_squared_to(t.global_position)
		if d2 > r2:
			continue
		var mult: float = 1.0
		if n.is_in_group(&"player") or n.is_in_group(NetHooks.GROUP_AVATAR):
			mult = self_mult
			if mult <= 0.0:
				continue
		if query != null:
			query.to = t.global_position
			var res: Dictionary = space.intersect_ray(query)
			if not res.is_empty() and res.get("collider") != n:
				continue  # Mur entre le centre et la cible.
		var amount: float = falloff_damage(sqrt(d2), radius, damage, min_frac) * mult
		if amount <= 0.0:
			continue
		n.call("take_damage", amount, source if is_instance_valid(source) else null)
		hit.append(t)
		out_amounts.append(amount)
	return hit
