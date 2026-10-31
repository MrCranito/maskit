class_name DamageMeter
extends RefCounted
## Compteur de dégâts d'un mannequin de l'arène : dernier coup, total, DPS glissant.
## DPS = somme des dégâts reçus pendant les `window` dernières secondes ÷ `window`
## ([test_arena] dps_window, 5 s). Horloge fournie par l'appelant (testable).

var window: float = 5.0
var total: float = 0.0
var last_hit: float = 0.0
var hits: int = 0
## [[t, montant], …] des coups encore dans la fenêtre.
var _recent: Array = []


func _init(p_window: float = 5.0) -> void:
	window = maxf(p_window, 0.1)


func add(amount: float, t: float) -> void:
	if amount <= 0.0:
		return
	total += amount
	last_hit = amount
	hits += 1
	_recent.append([t, amount])
	_prune(t)


func dps(t: float) -> float:
	_prune(t)
	var s := 0.0
	for e: Array in _recent:
		s += float(e[1])
	return s / window


func reset() -> void:
	total = 0.0
	last_hit = 0.0
	hits = 0
	_recent.clear()


func _prune(t: float) -> void:
	while not _recent.is_empty() and float(_recent[0][0]) <= t - window:
		_recent.pop_front()


## « 12 · 34 DPS · 1 234 » (dernier coup, DPS sur la fenêtre, total).
func text(t: float) -> String:
	return "Dernier %d   DPS %d   Total %s" % [roundi(last_hit), roundi(dps(t)), MainMenu.format_thousands(roundi(total))]
