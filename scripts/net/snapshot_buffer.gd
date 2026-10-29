class_name SnapshotBuffer
extends RefCounted
## Tampon d'interpolation d'une entité distante (coéquipier) : anneau fixe d'échantillons
## (temps de l'émetteur, position, vitesse, visée), lu avec un retard `delay` pour toujours
## interpoler entre deux échantillons reçus ; au-delà du dernier, extrapolation bornée par la
## vitesse (`extrapolate_max`). Aucune allocation après la création.

const SIZE := 16

var times: PackedInt64Array = PackedInt64Array()
var positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var aims: PackedVector2Array = PackedVector2Array()
var count: int = 0
var _head: int = -1  ## Index du plus récent.
## Retard d'interpolation (s) et extrapolation maximale (s).
var delay: float = 0.1
var extrapolate_max: float = 0.15
## Saut au-delà duquel on téléporte (changement d'étage, sortie de cachette).
var snap_distance: float = 320.0


func _init() -> void:
	times.resize(SIZE)
	positions.resize(SIZE)
	velocities.resize(SIZE)
	aims.resize(SIZE)


func clear() -> void:
	count = 0
	_head = -1


## Ajoute un échantillon (temps de l'émetteur en ms). Les échantillons en retard ou en double
## sont ignorés. Renvoie vrai si le saut depuis le précédent impose une téléportation.
func push(t_ms: int, p: Vector2, v: Vector2, aim: Vector2) -> bool:
	var teleport := false
	if count > 0:
		if t_ms <= times[_head]:
			return false
		teleport = positions[_head].distance_to(p) > snap_distance
		if teleport:
			count = 0
	_head = (_head + 1) % SIZE
	times[_head] = t_ms
	positions[_head] = p
	velocities[_head] = v
	aims[_head] = aim
	count = mini(count + 1, SIZE)
	return teleport


func latest_time() -> int:
	return times[_head] if count > 0 else 0


func latest_position() -> Vector2:
	return positions[_head] if count > 0 else Vector2.ZERO


## Échantillon i (0 = plus ancien, count-1 = plus récent).
func _idx(i: int) -> int:
	return (_head - (count - 1) + i + SIZE * 2) % SIZE


## Position interpolée au temps `t_ms` (temps de l'émetteur). `out_aim` / `out_vel` : sorties
## facultatives via le tableau `out` [aim, vel] réutilisé par l'appelant.
func sample(t_ms: float, out: PackedVector2Array) -> Vector2:
	if count == 0:
		return Vector2.ZERO
	var newest := _idx(count - 1)
	if count == 1 or t_ms >= float(times[newest]):
		# Extrapolation bornée à partir du plus récent.
		var dt := clampf((t_ms - float(times[newest])) / 1000.0, 0.0, extrapolate_max)
		if out.size() >= 2:
			out[0] = aims[newest]
			out[1] = velocities[newest]
		return positions[newest] + velocities[newest] * dt
	var oldest := _idx(0)
	if t_ms <= float(times[oldest]):
		if out.size() >= 2:
			out[0] = aims[oldest]
			out[1] = velocities[oldest]
		return positions[oldest]
	# Recherche des deux échantillons qui encadrent t (du plus récent vers le plus ancien).
	for i: int in range(count - 1, 0, -1):
		var b := _idx(i)
		var a := _idx(i - 1)
		if t_ms >= float(times[a]):
			var span := float(times[b] - times[a])
			var k := clampf((t_ms - float(times[a])) / maxf(span, 1.0), 0.0, 1.0)
			if out.size() >= 2:
				out[0] = aims[a].slerp(aims[b], k) if aims[a] != Vector2.ZERO and aims[b] != Vector2.ZERO else aims[b]
				out[1] = velocities[a].lerp(velocities[b], k)
			return positions[a].lerp(positions[b], k)
	return positions[newest]


## Synchronisation d'horloge : estime le décalage horloge locale − horloge distante (ms) en
## gardant le minimum observé (= latence la plus faible), relâché lentement pour suivre une
## dérive. Temps de rendu = maintenant (distant) − retard d'interpolation.
class ClockSync extends RefCounted:
	var offset: float = 0.0
	var has_offset: bool = false
	## Relâchement (ms par échantillon) vers une latence plus élevée.
	var relax: float = 0.5

	func observe(remote_ms: int, local_ms: int) -> void:
		var o := float(local_ms - remote_ms)
		if not has_offset or o < offset:
			offset = o
			has_offset = true
		else:
			offset = minf(offset + relax, o)

	func remote_now(local_ms: int) -> float:
		return float(local_ms) - offset

	func reset() -> void:
		has_offset = false
		offset = 0.0
