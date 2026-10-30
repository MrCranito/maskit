class_name WeaponLoadout
extends RefCounted
## Logique pure des armes tenues en raid (aucun nœud, testable) :
## emplacements (≤ [arsenal] loadout_slots), emplacement courant, munitions conservées
## par emplacement, cadence (délai entre deux tirs), rechargement (annulé au changement).
## Chargeur de taille 0 = illimité : get_ammo() renvoie alors -1.

var slots: Array[WeaponData] = []
var ammo: PackedInt32Array = PackedInt32Array()
var current: int = 0
## Délai restant avant le prochain tir (s).
var cooldown: float = 0.0
var reload_left: float = 0.0
var reload_total: float = 0.0
## Dispersion accumulée en tir continu (°) de l'arme courante, et temps depuis le dernier tir.
## Remise à 0 au changement d'arme. Voir WeaponData.spread_bloom_*.
var bloom: float = 0.0
var since_shot: float = 999.0
## Emplacement d'équipement (grenade, mine, C4, drone) et charges restantes.
var gadget: WeaponData = null
var gadget_charges: int = 0


func _init(slot_count: int = 3) -> void:
	resize(slot_count)


func resize(slot_count: int) -> void:
	var n: int = maxi(slot_count, 1)
	slots.resize(n)
	ammo.resize(n)
	current = clampi(current, 0, n - 1)


func size() -> int:
	return slots.size()


static func magazine_of(w: WeaponData) -> int:
	return maxi(w.magazine_size, 0) if w != null else 0


## Remplit les emplacements depuis `list` (null autorisé), chargeurs pleins, premier
## emplacement occupé sélectionné.
func set_weapons(list: Array) -> void:
	# Les équipements de la liste vont dans l'emplacement d'équipement.
	var guns: Array[WeaponData] = []
	for v: Variant in list:
		var w := v as WeaponData
		if w != null and w.is_gadget():
			if gadget == null:
				set_gadget(w)
			continue
		guns.append(w)
	for i: int in slots.size():
		var w: WeaponData = guns[i] if i < guns.size() else null
		slots[i] = w
		ammo[i] = magazine_of(w)
	current = 0
	for i: int in slots.size():
		if slots[i] != null:
			current = i
			break
	cancel_reload()
	cooldown = 0.0


func get_weapons() -> Array[WeaponData]:
	return slots.duplicate()


func current_weapon() -> WeaponData:
	return slots[current] if current >= 0 and current < slots.size() else null


func weapon_count() -> int:
	var n: int = 0
	for w: WeaponData in slots:
		if w != null:
			n += 1
	return n


## Change d'emplacement (false si vide, identique ou hors bornes). Annule le rechargement ;
## les munitions de chaque emplacement sont conservées.
func switch_to(slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or slot == current or slots[slot] == null:
		return false
	cancel_reload()
	current = slot
	cooldown = 0.0
	bloom = 0.0
	return true


## Prochain emplacement occupé dans le sens `step` (+1 / -1), -1 s'il n'y en a pas d'autre.
func cycle_slot(step: int = 1) -> int:
	var n: int = slots.size()
	for k: int in range(1, n):
		var i: int = wrapi(current + k * signi(step if step != 0 else 1), 0, n)
		if slots[i] != null:
			return i
	return -1


## Place `w` dans l'emplacement courant (chargeur plein) et renvoie l'arme remplacée (ou null).
func equip_into_current(w: WeaponData) -> WeaponData:
	var old: WeaponData = slots[current]
	slots[current] = w
	ammo[current] = magazine_of(w)
	cancel_reload()
	cooldown = 0.0
	return old


## Premier emplacement vide (-1 si aucun).
func first_empty_slot() -> int:
	for i: int in slots.size():
		if slots[i] == null:
			return i
	return -1


## Remplace l'arme courante en gardant les munitions (bornées au nouveau chargeur) :
## compatibilité `Player.weapon = ...` (modificateurs de carte).
func replace_current(w: WeaponData) -> void:
	slots[current] = w
	var mag: int = magazine_of(w)
	ammo[current] = clampi(ammo[current], 0, mag) if mag > 0 else 0


## Exemplaires tenus (affixes compris) + l'équipement s'il lui reste des charges (extraction).
func carried_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w: WeaponData in slots:
		if w != null and not String(w.id).is_empty():
			out.append(w)
	if gadget != null and gadget_charges > 0 and not String(gadget.id).is_empty():
		out.append(gadget)
	return out


## Ids des armes tenues + de l'équipement s'il lui reste des charges (extraction).
func carried_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for w: WeaponData in slots:
		if w != null and not String(w.id).is_empty():
			out.append(w.id)
	if gadget != null and gadget_charges > 0 and not String(gadget.id).is_empty():
		out.append(gadget.id)
	return out


# --- Équipement -----------------------------------------------------------------

static func charges_of(w: WeaponData) -> int:
	return maxi(w.charges, 1) if w != null else 0


## Place `w` dans l'emplacement d'équipement (charges pleines) ; renvoie l'ancien.
func set_gadget(w: WeaponData) -> WeaponData:
	var old: WeaponData = gadget
	gadget = w
	gadget_charges = charges_of(w)
	return old


func has_gadget_charge() -> bool:
	return gadget != null and gadget_charges > 0


## Consomme une charge (false s'il n'y en a plus).
func consume_gadget_charge() -> bool:
	if not has_gadget_charge():
		return false
	gadget_charges -= 1
	return true


func get_ammo() -> int:
	var w: WeaponData = current_weapon()
	if w == null:
		return 0
	return ammo[current] if magazine_of(w) > 0 else -1


func get_magazine() -> int:
	return magazine_of(current_weapon())


func has_ammo() -> bool:
	var w: WeaponData = current_weapon()
	return w != null and (magazine_of(w) <= 0 or ammo[current] > 0)


func needs_reload() -> bool:
	var w: WeaponData = current_weapon()
	return w != null and magazine_of(w) > 0 and ammo[current] <= 0


func is_reloading() -> bool:
	return reload_left > 0.0


## 0 → 1 pendant le rechargement, 0 sinon.
func reload_progress() -> float:
	if reload_left <= 0.0 or reload_total <= 0.0:
		return 0.0
	return clampf(1.0 - reload_left / reload_total, 0.0, 1.0)


## Commence un rechargement (false si inutile, impossible ou déjà en cours).
func start_reload(time_mult: float = 1.0) -> bool:
	var w: WeaponData = current_weapon()
	if w == null or is_reloading():
		return false
	var mag: int = magazine_of(w)
	if mag <= 0 or ammo[current] >= mag:
		return false
	reload_total = maxf(w.reload_time * maxf(time_mult, 0.0), 0.01)
	reload_left = reload_total
	return true


func cancel_reload() -> void:
	reload_left = 0.0
	reload_total = 0.0


func can_fire() -> bool:
	return cooldown <= 0.0 and not is_reloading() and has_ammo()


## Consomme une munition et arme le délai de cadence.
func consume_shot() -> void:
	var w: WeaponData = current_weapon()
	if w == null:
		return
	cooldown = w.get_fire_interval()
	since_shot = 0.0
	bloom = minf(bloom + w.spread_bloom_per_shot * bloom_mult(), w.spread_bloom_max * bloom_mult())
	if magazine_of(w) > 0:
		ammo[current] = maxi(ammo[current] - 1, 0)


## Avance le temps. Renvoie true si un rechargement vient de se terminer.
func tick(delta: float) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	since_shot += delta
	if bloom > 0.0:
		var w0: WeaponData = current_weapon()
		# La dispersion redescend dès qu'on cesse de tirer (un peu plus d'un intervalle de tir).
		var hold: float = Balance.get_float("player", "spread_recovery_delay", 0.08)
		if w0 == null:
			bloom = 0.0
		elif since_shot > w0.get_fire_interval() + hold:
			bloom = maxf(bloom - w0.spread_bloom_recovery * delta, 0.0)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			reload_left = 0.0
			reload_total = 0.0
			ammo[current] = magazine_of(current_weapon())
			return true
	return false


## Multiplicateur global du bloom ([player] spread_bloom_mult).
static func bloom_mult() -> float:
	return maxf(Balance.get_float("player", "spread_bloom_mult", 1.0), 0.0)


## Imprécision effective (±°) de l'arme courante pour une vitesse relative `move_ratio`.
func current_inaccuracy(move_ratio: float) -> float:
	var w: WeaponData = current_weapon()
	if w == null:
		return 0.0
	return w.effective_inaccuracy(bloom, move_ratio, maxf(Balance.get_float("player", "spread_move_mult", 1.0), 0.0))
