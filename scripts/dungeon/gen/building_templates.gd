extends RefCounted
## Gabarits de bâtiments Far West (plans locaux, en cases).
##
## Repère local d'un plan : (0,0) = coin haut-gauche de l'emprise, murs compris.
## La FAÇADE (côté rue) est toujours la ligne du bas (y = size.y - 1) ; le
## générateur retourne le plan verticalement pour les bâtiments au sud de la rue
## et peut le retourner horizontalement pour varier.
## Les salles sont séparées par des cloisons d'une case ; on ne passe d'une salle
## à l'autre que par des portes.

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")

const OUTSIDE := -1


class PRoom:
	var rect: Rect2i          ## Intérieur (sans les murs), repère local
	var type: StringName      ## Type fixe, ou &"" = à tirer (générique)
	var name: String
	var role: StringName      ## Sert à l'ameublement (saloon_hall, bank_vault…)


class PDoor:
	var cell: Vector2i
	var vertical: bool
	var a: int                ## Indice de salle, OUTSIDE = rue
	var b: int
	var state: int = FloorLayout.DoorState.CLOSED
	var key_id: StringName = &""


class Plan:
	var archetype: StringName
	var size: Vector2i
	var rooms: Array[PRoom] = []
	var doors: Array[PDoor] = []
	var stairs: Array[Vector2i] = []   ## Escaliers (repère local)
	var stairs_up: Array[bool] = []
	var has_upper: bool = false

	func add_room(r: Rect2i, type: StringName, name: String, role: StringName) -> int:
		var pr := PRoom.new()
		pr.rect = r
		pr.type = type
		pr.name = name
		pr.role = role
		rooms.append(pr)
		return rooms.size() - 1

	func add_stairs(c: Vector2i, up: bool) -> void:
		stairs.append(c)
		stairs_up.append(up)

	func front_room_ids() -> Array[int]:
		var out: Array[int] = []
		for i in rooms.size():
			if rooms[i].rect.end.y == size.y - 1:
				out.append(i)
		return out


## Construit le plan d'un archétype. `ctx` : { super_budget: int } (décrémenté si
## une salle super_loot verrouillée est créée).
static func build(archetype: StringName, rng: RandomNumberGenerator, ctx: Dictionary) -> Plan:
	var sr := Cfg.size_range(archetype)
	var w := rng.randi_range(int(sr[0]), int(sr[1]))
	var h := rng.randi_range(int(sr[2]), int(sr[3]))
	var p: Plan
	match archetype:
		&"saloon": p = _saloon(w, h, rng)
		&"bank": p = _bank(w, h, rng, ctx)
		&"sheriff": p = _sheriff(w, h, rng, ctx)
		&"store": p = _store(w, h, rng)
		&"hotel": p = _hotel(w, h, rng)
		&"stable": p = _stable(w, h, rng)
		&"church": p = _church(w, h, rng)
		&"mine": p = _mine(w, h, rng)
		_: p = _store(w, h, rng)
	p.archetype = archetype
	return p


# --- Aides ---------------------------------------------------------------

## Porte entre deux salles qui partagent une cloison (détectée automatiquement).
## Évite les positions dont une case de passage est un escalier.
static func link(p: Plan, rng: RandomNumberGenerator, i: int, j: int, state: int = FloorLayout.DoorState.CLOSED, key: StringName = &"") -> bool:
	var a := p.rooms[i].rect
	var b := p.rooms[j].rect
	var cands: Array[Vector2i] = []
	var vertical := false
	if a.end.y + 1 == b.position.y or b.end.y + 1 == a.position.y:
		var wy := a.end.y if a.end.y + 1 == b.position.y else b.end.y
		for x in range(maxi(a.position.x, b.position.x), mini(a.end.x, b.end.x)):
			cands.append(Vector2i(x, wy))
	elif a.end.x + 1 == b.position.x or b.end.x + 1 == a.position.x:
		vertical = true
		var wx := a.end.x if a.end.x + 1 == b.position.x else b.end.x
		for y in range(maxi(a.position.y, b.position.y), mini(a.end.y, b.end.y)):
			cands.append(Vector2i(wx, y))
	var ok: Array[Vector2i] = []
	for c in cands:
		if not _near_stairs(p, c, vertical):
			ok.append(c)
	if ok.is_empty():
		return false
	var d := PDoor.new()
	d.cell = ok[rng.randi_range(0, ok.size() - 1)]
	d.vertical = vertical
	d.a = i
	d.b = j
	d.state = state
	d.key_id = key
	if key != &"":
		d.state = FloorLayout.DoorState.LOCKED
	p.doors.append(d)
	return true


static func _near_stairs(p: Plan, c: Vector2i, vertical: bool) -> bool:
	var through: Array[Vector2i] = []
	if vertical:
		through = [c + Vector2i.LEFT, c + Vector2i.RIGHT]
	else:
		through = [c + Vector2i.UP, c + Vector2i.DOWN]
	for s in p.stairs:
		if s == c or through.has(s):
			return true
	for d in p.doors:
		if d.cell.distance_squared_to(c) <= 2:
			return true
	return false


## 1 à `max_count` portes en façade (ligne du bas), espacées d'au moins 3 cases.
static func front_doors(p: Plan, rng: RandomNumberGenerator, max_count: int) -> void:
	var fronts := p.front_room_ids()
	var count := rng.randi_range(1, maxi(1, max_count))
	var used: Array[int] = []
	for n in count:
		var ri: int = fronts[rng.randi_range(0, fronts.size() - 1)] if n > 0 else fronts[0]
		var r := p.rooms[ri].rect
		var cands: Array[int] = []
		for x in range(r.position.x, r.end.x):
			var far := true
			for u in used:
				if absi(u - x) < 3:
					far = false
			if far and not p.stairs.has(Vector2i(x, p.size.y - 2)):
				cands.append(x)
		if cands.is_empty():
			continue
		var x: int = cands[rng.randi_range(0, cands.size() - 1)]
		used.append(x)
		var d := PDoor.new()
		d.cell = Vector2i(x, p.size.y - 1)
		d.vertical = false
		d.a = OUTSIDE
		d.b = ri
		d.state = FloorLayout.DoorState.CLOSED
		p.doors.append(d)


## Découpe une largeur `total` en `k` parts (≥ min_w) séparées par des cloisons.
static func split_widths(total: int, k: int, min_w: int, rng: RandomNumberGenerator) -> Array[int]:
	var avail := total - (k - 1)
	var out: Array[int] = []
	for i in k:
		out.append(min_w)
	var rest := avail - min_w * k
	while rest > 0:
		out[rng.randi_range(0, k - 1)] += 1
		rest -= 1
	return out


static func _take_super(ctx: Dictionary) -> bool:
	if int(ctx.get("super_budget", 0)) > 0:
		ctx["super_budget"] = int(ctx["super_budget"]) - 1
		return true
	return false


# --- Gabarits ------------------------------------------------------------

## Saloon : grande salle (bar, piano, tables) + arrière-salle + bureau du patron
## avec l'escalier vers l'étage.
static func _saloon(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	p.has_upper = true
	var bd := rng.randi_range(3, 4)
	var sx := rng.randi_range(4, w - 6)
	var hall := p.add_room(Rect2i(1, bd + 2, w - 2, h - 3 - bd), &"combat", "Salle du saloon", &"saloon_hall")
	var back := p.add_room(Rect2i(1, 1, sx - 1, bd), &"", "Arrière-salle", &"storage")
	var office := p.add_room(Rect2i(sx + 1, 1, w - 2 - sx, bd), &"", "Bureau du patron", &"saloon_office")
	p.add_stairs(Vector2i(w - 2, 1), true)
	link(p, rng, hall, back)
	link(p, rng, hall, office)
	front_doors(p, rng, 2)
	return p


## Banque : hall + bureau + coffre-fort verrouillé (super_loot, key_bank_vault).
static func _bank(w: int, h: int, rng: RandomNumberGenerator, ctx: Dictionary) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var vd := rng.randi_range(3, 4)
	var sx := rng.randi_range(4, w - 5)
	var hall := p.add_room(Rect2i(1, vd + 2, w - 2, h - 3 - vd), &"combat", "Hall de la banque", &"bank_hall")
	var left := Rect2i(1, 1, sx - 1, vd)
	var right := Rect2i(sx + 1, 1, w - 2 - sx, vd)
	var vault_left := rng.randf() < 0.5
	var office := p.add_room(right if vault_left else left, &"", "Bureau du directeur", &"bank_office")
	var sealed := _take_super(ctx)
	var vault := p.add_room(left if vault_left else right, &"super_loot" if sealed else &"loot", "Coffre-fort", &"bank_vault")
	link(p, rng, hall, office)
	if sealed:
		link(p, rng, hall, vault, FloorLayout.DoorState.LOCKED, &"key_bank_vault")
	else:
		link(p, rng, hall, vault)
	front_doors(p, rng, 1)
	return p


## Bureau du shérif : bureau + 2-3 cellules à barreaux (+ armurerie scellée possible).
static func _sheriff(w: int, h: int, rng: RandomNumberGenerator, ctx: Dictionary) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var cd := rng.randi_range(3, 4)
	var k := clampi((w - 1) / 4, 2, 3)
	var office := p.add_room(Rect2i(1, cd + 2, w - 2, h - 3 - cd), &"combat", "Bureau du shérif", &"sheriff_office")
	var widths := split_widths(w - 2, k, 3, rng)
	var armory := k == 3 and rng.randf() < Cfg.getf("sheriff_armory_chance", 0.35) and _take_super(ctx)
	var x := 1
	for i in k:
		var r := Rect2i(x, 1, widths[i], cd)
		x += widths[i] + 1
		if armory and i == k - 1:
			var ar := p.add_room(r, &"super_loot", "Armurerie", &"sheriff_armory")
			link(p, rng, office, ar, FloorLayout.DoorState.LOCKED, &"key_sheriff_armory")
		else:
			var ci := p.add_room(r, &"", "Cellule %d" % (i + 1), &"jail_cell")
			link(p, rng, office, ci)
	front_doors(p, rng, 1)
	return p


## Magasin général : boutique + réserve (+ bureau).
static func _store(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var sd := rng.randi_range(3, 4)
	var shop := p.add_room(Rect2i(1, sd + 2, w - 2, h - 3 - sd), &"", "Boutique", &"store_shop")
	if w - 2 >= 10 and rng.randf() < 0.5:
		var sx := rng.randi_range(5, w - 5)
		var res := p.add_room(Rect2i(1, 1, sx - 1, sd), &"loot", "Réserve", &"storage")
		var off := p.add_room(Rect2i(sx + 1, 1, w - 2 - sx, sd), &"", "Bureau du marchand", &"office")
		link(p, rng, shop, res)
		link(p, rng, shop, off)
	else:
		var res2 := p.add_room(Rect2i(1, 1, w - 2, sd), &"loot", "Réserve", &"storage")
		link(p, rng, shop, res2)
	front_doors(p, rng, 1)
	return p


## Hôtel : réception + couloir intérieur (escalier) + salle à manger / bureau.
static func _hotel(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	p.has_upper = true
	var rd := mini(rng.randi_range(4, 5), h - 9)
	var rec_y := h - 1 - rd
	var cy := rec_y - 3
	var rec := p.add_room(Rect2i(1, rec_y, w - 2, rd), &"", "Réception", &"hotel_reception")
	var cor := p.add_room(Rect2i(1, cy, w - 2, 2), &"corridor", "Couloir de l'hôtel", &"corridor")
	var sx := 1 if rng.randf() < 0.5 else w - 2
	p.add_stairs(Vector2i(sx, cy), true)
	link(p, rng, rec, cor)
	var top_h := cy - 2
	if w - 2 >= 9:
		var widths := split_widths(w - 2, 2, 4, rng)
		var a := p.add_room(Rect2i(1, 1, widths[0], top_h), &"", "Salle à manger", &"hotel_dining")
		var b := p.add_room(Rect2i(2 + widths[0], 1, widths[1], top_h), &"", "Bureau du gérant", &"office")
		link(p, rng, cor, a)
		link(p, rng, cor, b)
	else:
		var a2 := p.add_room(Rect2i(1, 1, w - 2, top_h), &"", "Salle à manger", &"hotel_dining")
		link(p, rng, cor, a2)
	front_doors(p, rng, 2)
	return p


## Écurie : grand espace + 2-3 box.
static func _stable(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var bd := rng.randi_range(3, 4)
	var main := p.add_room(Rect2i(1, bd + 2, w - 2, h - 3 - bd), &"combat", "Écurie", &"stable_main")
	var k := clampi((w - 1) / 4, 2, 3)
	var widths := split_widths(w - 2, k, 3, rng)
	var x := 1
	for i in k:
		var bi := p.add_room(Rect2i(x, 1, widths[i], bd), &"", "Box %d" % (i + 1), &"stable_box")
		x += widths[i] + 1
		link(p, rng, main, bi)
	front_doors(p, rng, 2)
	return p


## Église : nef (bancs, autel) + sacristie.
static func _church(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var nave_type: StringName = &"rest" if rng.randf() < Cfg.getf("church_rest_chance", 0.5) else &"combat"
	var nave := p.add_room(Rect2i(1, 5, w - 2, h - 6), nave_type, "Nef", &"church_nave")
	var sac := p.add_room(Rect2i(1, 1, w - 2, 3), &"loot", "Sacristie", &"church_sacristy")
	link(p, rng, nave, sac)
	front_doors(p, rng, 1)
	return p


## Entrée de mine : salle d'entrée avec escalier vers le sous-sol (+ cabane à outils).
static func _mine(w: int, h: int, rng: RandomNumberGenerator) -> Plan:
	var p := Plan.new()
	p.size = Vector2i(w, h)
	var ent_rect := Rect2i(1, 1, w - 2, h - 2)
	var tools := -1
	if w >= 10 and rng.randf() < 0.6:
		if rng.randf() < 0.5:
			ent_rect = Rect2i(5, 1, w - 6, h - 2)
			tools = p.add_room(Rect2i(1, 1, 3, h - 2), &"loot", "Cabane à outils", &"mine_tools")
		else:
			ent_rect = Rect2i(1, 1, w - 6, h - 2)
			tools = p.add_room(Rect2i(w - 4, 1, 3, h - 2), &"loot", "Cabane à outils", &"mine_tools")
	var ent := p.add_room(ent_rect, &"combat", "Entrée de la mine", &"mine_entrance")
	p.add_stairs(Vector2i(ent_rect.position.x + ent_rect.size.x / 2, 1), false)
	if tools >= 0:
		link(p, rng, ent, tools)
	# La façade appartient à la salle d'entrée.
	var fronts := p.front_room_ids()
	fronts.erase(tools)
	var r := p.rooms[ent].rect
	var d := PDoor.new()
	d.cell = Vector2i(rng.randi_range(r.position.x, r.end.x - 1), h - 1)
	d.a = OUTSIDE
	d.b = ent
	p.doors.append(d)
	return p
