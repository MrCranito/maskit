class_name MapRotation
extends RefCounted
## Rotation des cartes, DÉTERMINISTE depuis l'heure UTC (aucun serveur : tous les joueurs
## voient les mêmes cartes au même moment).
##   permanent : toujours disponibles.
##   weekly    : semaine ISO UTC (lundi 00:00 UTC → lundi suivant) ; [maps] weekly_count cartes
##               tirées dans le pool, pondérées par MapCard.weight, sans doublon,
##               RNG seedé par hash("<salt>:weekly:<n° de semaine>").
##   monthly   : mois calendaire UTC ; [maps] monthly_count cartes, même principe.
##   event     : la journée est découpée en créneaux de [maps] event_period_hours, décalés de
##               event_offset_hours ; chaque créneau ouvre UN événement pendant
##               event_duration_hours (tiré par hash("<salt>:event:<n° de créneau>"), jamais
##               le même que le créneau précédent).
## Les cartes dont le monde manque restent dans la rotation (elle ne dépend pas des
## fichiers locaux) ; l'interface les grise (« Bientôt »).
## Debug : GameState.debug_time_override (> 0) ou [maps] debug_unix_time / debug_time_offset_hours.

const DAY := 86400
const WEEK := 7 * DAY
## 1970-01-01 était un jeudi : décalage pour que la semaine commence le lundi.
const EPOCH_MONDAY_OFFSET := 3


# --- Heure ------------------------------------------------------------------------

## Heure UTC courante (secondes Unix), surchargeable pour le debug.
static func now() -> int:
	var gs: Node = _game_state()
	if gs != null:
		var o: Variant = gs.get("debug_time_override")
		if o != null and int(o) > 0:
			return int(o)
	var forced: int = int(Balance.get_value("maps", "debug_unix_time", 0))
	if forced > 0:
		return forced
	var offset_h: float = Balance.get_float("maps", "debug_time_offset_hours", 0.0)
	return int(Time.get_unix_time_from_system()) + int(offset_h * 3600.0)


# --- Périodes ---------------------------------------------------------------------

## Numéro de semaine ISO (continu depuis 1970) et bornes [début, fin[.
static func week_index(t: int) -> int:
	return floori(float(floori(float(t) / DAY) + EPOCH_MONDAY_OFFSET) / 7.0)


static func week_bounds(t: int) -> Vector2i:
	var start: int = week_index(t) * WEEK - EPOCH_MONDAY_OFFSET * DAY
	return Vector2i(start, start + WEEK)


## Index de mois (année × 12 + mois - 1) et bornes [début, fin[.
static func month_index(t: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	return int(d["year"]) * 12 + int(d["month"]) - 1


static func month_bounds(t: int) -> Vector2i:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	var y: int = int(d["year"])
	var m: int = int(d["month"])
	var start: int = Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var ny: int = y + (1 if m == 12 else 0)
	var nm: int = 1 if m == 12 else m + 1
	var end: int = Time.get_unix_time_from_datetime_dict({"year": ny, "month": nm, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return Vector2i(start, end)


static func event_period() -> int:
	return maxi(int(Balance.get_float("maps", "event_period_hours", 6.0) * 3600.0), 60)


static func event_duration() -> int:
	return clampi(int(Balance.get_float("maps", "event_duration_hours", 2.0) * 3600.0), 60, event_period())


static func event_offset() -> int:
	return int(Balance.get_float("maps", "event_offset_hours", 0.0) * 3600.0)


## Créneau d'événement contenant t (le créneau commence à slot × période + décalage).
static func event_slot(t: int) -> int:
	return floori(float(t - event_offset()) / float(event_period()))


static func event_slot_start(slot: int) -> int:
	return slot * event_period() + event_offset()


# --- Tirages ----------------------------------------------------------------------

static func _salt() -> String:
	return str(Balance.get_value("maps", "rotation_salt", "rdm"))


## Tirage pondéré sans doublon de `count` cartes du pool (ordre par id = déterministe).
static func draw(pool: Array[MapCard], count: int, key: String, exclude: Array[MapCard] = []) -> Array[MapCard]:
	var cands: Array[MapCard] = []
	for c: MapCard in pool:
		if not exclude.has(c) and c.weight > 0.0:
			cands.append(c)
	if cands.is_empty() and not exclude.is_empty():  # exclusion impossible : on l'ignore
		return draw(pool, count, key)
	cands.sort_custom(func(a: MapCard, b: MapCard) -> bool: return String(a.id) < String(b.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%s" % [_salt(), key]).hash()
	var out: Array[MapCard] = []
	for i: int in mini(count, cands.size()):
		var total := 0.0
		for c: MapCard in cands:
			total += c.weight
		var r: float = rng.randf() * total
		var pick: MapCard = cands[cands.size() - 1]
		for c: MapCard in cands:
			r -= c.weight
			if r <= 0.0:
				pick = c
				break
		out.append(pick)
		cands.erase(pick)
	return out


static func weekly_cards(t: int) -> Array[MapCard]:
	return draw(MapCard.by_category(MapCard.CATEGORY_WEEKLY),
		int(Balance.get_value("maps", "weekly_count", 2)), "weekly:%d" % week_index(t))


static func monthly_cards(t: int) -> Array[MapCard]:
	return draw(MapCard.by_category(MapCard.CATEGORY_MONTHLY),
		int(Balance.get_value("maps", "monthly_count", 1)), "monthly:%d" % month_index(t))


## Événement du créneau. Créneaux pairs : tirage pondéré direct ; créneaux impairs :
## tirage pondéré qui exclut les événements des deux créneaux pairs voisins. Deux
## créneaux consécutifs n'ont donc jamais le même événement (pool ≥ 3), sans récursion.
static func event_card_for_slot(slot: int) -> MapCard:
	var pool: Array[MapCard] = MapCard.by_category(MapCard.CATEGORY_EVENT)
	if pool.is_empty():
		return null
	var got: Array[MapCard]
	if posmod(slot, 2) == 0:
		got = draw(pool, 1, "event:%d" % slot)
	else:
		var around: Array[MapCard] = []
		around.append_array(draw(pool, 1, "event:%d" % (slot - 1)))
		around.append_array(draw(pool, 1, "event:%d" % (slot + 1)))
		got = draw(pool, 1, "event:%d" % slot, around)
	return got[0] if not got.is_empty() else null


# --- API --------------------------------------------------------------------------

## Cartes disponibles à l'instant t : [{card, category, starts_at, ends_at}]
## (ends_at = 0 : sans limite). Ordre : événement, hebdomadaires, mensuelles, permanentes ;
## seulement les catégories de [maps] categories.
static func available_cards(unix_time: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ev: Dictionary = active_event(unix_time)
	if not ev.is_empty():
		out.append(ev)
	if is_enabled(MapCard.CATEGORY_WEEKLY):
		var wb: Vector2i = week_bounds(unix_time)
		for c: MapCard in weekly_cards(unix_time):
			out.append(_entry(c, wb.x, wb.y))
	if is_enabled(MapCard.CATEGORY_MONTHLY):
		var mb: Vector2i = month_bounds(unix_time)
		for c: MapCard in monthly_cards(unix_time):
			out.append(_entry(c, mb.x, mb.y))
	if is_enabled(MapCard.CATEGORY_PERMANENT):
		for c: MapCard in MapCard.by_category(MapCard.CATEGORY_PERMANENT):
			out.append(_entry(c, 0, 0))
	return out


## Catégories proposées au joueur ([maps] categories), dans l'ordre de MapCard.CATEGORIES.
static func enabled_categories() -> Array[StringName]:
	var v: Variant = Balance.get_value("maps", "categories", [])
	var out: Array[StringName] = []
	for cat: StringName in MapCard.CATEGORIES:
		if not (v is Array) or (v as Array).is_empty() or (v as Array).has(String(cat)):
			out.append(cat)
	return out


static func is_enabled(cat: StringName) -> bool:
	return enabled_categories().has(cat)


## Cartes proposées au joueur : available_cards filtrées par [maps] only_ids (build de test ;
## liste vide = toutes les cartes).
static func offered_cards(unix_time: int) -> Array[Dictionary]:
	if DevMode.is_all_unlocked():
		return dev_all_cards()
	var all_cards := available_cards(unix_time)
	var only: Variant = Balance.get_value("maps", "only_ids", [])
	if not (only is Array) or (only as Array).is_empty():
		return all_cards
	var keep: Array[Dictionary] = []
	for e: Dictionary in all_cards:
		var card: MapCard = e.get("card") as MapCard
		if card != null and (only as Array).has(String(card.id)):
			keep.append(e)
	return keep


## Vrai si la rotation est restreinte (build de test) : pas d'annonce d'événement à venir.
static func is_restricted() -> bool:
	if DevMode.is_all_unlocked():
		return true
	var only: Variant = Balance.get_value("maps", "only_ids", [])
	return only is Array and not (only as Array).is_empty()


## Mode dev « Tout débloquer » : toutes les cartes jouables (et donc toutes les difficultés),
## ouvertes sans limite de temps, quelle que soit la rotation. Les cartes écartées par [maps]
## only_ids (prototypes sans rendu final : simulateur, camp d'entraînement, événements…) restent
## cachées. Ordre : événements, hebdo, mensuelles, permanentes.
static func dev_all_cards() -> Array[Dictionary]:
	var only: Variant = Balance.get_value("maps", "only_ids", [])
	var filter: bool = only is Array and not (only as Array).is_empty()
	var out: Array[Dictionary] = []
	for cat: StringName in enabled_categories():
		for c: MapCard in MapCard.by_category(cat):
			if filter and not (only as Array).has(String(c.id)):
				continue
			out.append(_entry(c, 0, 0))
	return out


## Événement actif à t ({} si aucun).
static func active_event(unix_time: int) -> Dictionary:
	var slot: int = event_slot(unix_time)
	var start: int = event_slot_start(slot)
	if unix_time >= start + event_duration():
		return {}
	var c: MapCard = event_card_for_slot(slot)
	return _entry(c, start, start + event_duration()) if c != null else {}


## Prochain événement qui n'a pas encore commencé ({card, category, starts_at, ends_at}).
static func next_event(unix_time: int) -> Dictionary:
	var slot: int = event_slot(unix_time) + 1
	var c: MapCard = event_card_for_slot(slot)
	if c == null:
		return {}
	var start: int = event_slot_start(slot)
	return _entry(c, start, start + event_duration())


## Secondes restantes avant la fin de l'entrée (-1 = sans limite, 0 = terminée).
static func time_left(entry: Dictionary, unix_time: int = -1) -> int:
	var end: int = int(entry.get("ends_at", 0))
	if end <= 0:
		return -1
	var t: int = unix_time if unix_time >= 0 else now()
	return maxi(end - t, 0)


## L'entrée est-elle jouable à t (période en cours) ?
static func is_active(entry: Dictionary, unix_time: int) -> bool:
	var end: int = int(entry.get("ends_at", 0))
	return unix_time >= int(entry.get("starts_at", 0)) and (end <= 0 or unix_time < end)


static func _entry(c: MapCard, start: int, end: int) -> Dictionary:
	return {"card": c, "category": c.category, "starts_at": start, "ends_at": end}


# --- Format -----------------------------------------------------------------------

## « 01:23:45 » (heures non bornées).
static func format_hms(seconds: int) -> String:
	var s: int = maxi(seconds, 0)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## « 3 j 4 h », « 3 h 12 », « 12 min », « 45 s ».
static func format_short(seconds: int) -> String:
	var s: int = maxi(seconds, 0)
	if s >= DAY:
		return "%d j %d h" % [s / DAY, (s % DAY) / 3600]
	if s >= 3600:
		return "%d h %02d" % [s / 3600, (s / 60) % 60]
	if s >= 60:
		return "%d min" % (s / 60)
	return "%d s" % s


static func _game_state() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(^"GameState") if ml != null and ml.root != null else null
