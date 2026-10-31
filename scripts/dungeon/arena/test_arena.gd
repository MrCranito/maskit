class_name TestArena
extends Node
## « Arène de test » (mode dev, DevMode.is_available) : carte dédiée au test des armes et des
## objets, jouée dans la scène de raid habituelle (Raid + MapCard + WorldData + générateur et
## décor d'arène). Ce nœud, attaché au Raid quand le monde est l'arène, ajoute :
##  - mannequins d'entraînement (ArenaDummy) immobiles et mobiles : dernier coup, DPS sur 5 s, total ;
##  - apparition à la demande d'ennemis de chaque archétype ([test_arena] archetypes) ;
##  - râtelier (ArenaPanel) : prendre n'importe quelle arme du catalogue ou n'importe quel objet,
##    changer de skin d'arme (affichage seulement, le profil n'est pas touché) ;
##  - munitions infinies et invincibilité activables, brouillard désactivable ;
##  - remise à zéro, sortie libre vers le menu.
## Rien ne compte : pas de Profile.start_raid (l'arsenal reste dans la réserve), pas de mort ni
## d'extraction, victimes non comptées (GameState.in_test_arena), aucune sauvegarde.

const BIOME := &"test_arena"
const CARD_PATH := "res://data/maps/dev/test_arena.tres"

## Mannequins (level design, fractions de la salle intérieure) : position, mobile, apparence.
const DUMMIES: Array[Dictionary] = [
	{"at": Vector2(0.37, 0.66), "moving": false, "look": TargetDummy.Look.MANNEQUIN},
	{"at": Vector2(0.5, 0.6), "moving": false, "look": TargetDummy.Look.GOLEM},
	{"at": Vector2(0.63, 0.66), "moving": true, "look": TargetDummy.Look.MANNEQUIN},
]
## Zone d'apparition des ennemis à la demande (fraction de la salle intérieure).
const ENEMY_ZONE := Rect2(0.12, 0.05, 0.76, 0.12)

var raid: Raid = null
var panel: ArenaPanel = null
var dummies: Array[ArenaDummy] = []
var spawned: Array[Node2D] = []
var god_mode: bool = true
var infinite_ammo: bool = true
var fog_enabled: bool = false
var _spawn_count: int = 0


## Le monde est-il l'arène de test ?
static func is_arena_world(world: Resource) -> bool:
	return world != null and StringName(world.get("biome")) == BIOME


## Carte de l'arène (null si absente ou hors mode dev).
static func card() -> MapCard:
	if not DevMode.is_available() or not ResourceLoader.exists(CARD_PATH):
		return null
	return load(CARD_PATH) as MapCard


static func is_arena_card(c: Resource) -> bool:
	return c != null and c is MapCard and (c as MapCard).id == &"dev_test_arena"


## Entrée du sélecteur de cartes (format MapRotation : ouverte sans limite) ; [] hors mode dev.
static func rotation_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := card()
	if c != null:
		out.append({"card": c, "category": c.category, "starts_at": 0, "ends_at": 0})
	return out


## Lancement depuis le sélecteur : pas d'arsenal de départ ni de Profile.start_raid, on part avec
## les armes de l'arsenal choisi (copies : la réserve n'est pas touchée), sac vide.
static func launch(from: Node, c: MapCard) -> void:
	GameState.set_current_map(c)
	GameState.raid_inventory = Inventory.from_balance()
	GameState.raid_weapons = Profile.get_loadout_weapons()
	GameState.raid_gadget = Profile.get_loadout_gadget()
	MenuKit.go_to(from, MenuKit.RAID_SCENE)


static func attach(p_raid: Raid) -> TestArena:
	var a := TestArena.new()
	a.name = "TestArena"
	a.raid = p_raid
	p_raid.add_child(a)
	return a


func _ready() -> void:
	GameState.in_test_arena = true
	god_mode = bool(Balance.get_value("test_arena", "god_mode_default", true))
	infinite_ammo = bool(Balance.get_value("test_arena", "infinite_ammo_default", true))
	fog_enabled = bool(Balance.get_value("test_arena", "fog_default", false))
	_spawn_dummies()
	_apply_player_flags()
	# Mini-carte inutile dans une seule salle sans brouillard.
	if raid.minimap != null:
		raid.minimap.set_obscured(&"arena", true)
	set_fog(fog_enabled)
	if raid.ui_layer != null:
		panel = ArenaPanel.new(self)
		raid.ui_layer.add_child(panel)


func _exit_tree() -> void:
	GameState.in_test_arena = false


func _inner() -> Rect2i:
	return ArenaGenerator.inner_rect(raid.layout)


func _world_at(f: Vector2) -> Vector2:
	return FloorLayout.cell_to_world(ArenaGenerator.cell_at(_inner(), f))


func _spawn_dummies() -> void:
	for d: Dictionary in DUMMIES:
		var dm := ArenaDummy.new()
		dm.name = "ArenaDummy%d" % dummies.size()
		dm.variant = d["look"]
		dm.moving = bool(d["moving"])
		dm.position = _world_at(d["at"] as Vector2)
		raid.enemies_container.add_child(dm)
		dummies.append(dm)


# --- Réglages -----------------------------------------------------------------------

func _player() -> Node:
	return raid.player if is_instance_valid(raid.player) else null


func _apply_player_flags() -> void:
	var p := _player()
	if p == null:
		return
	p.set("god_mode", god_mode)
	var lo: Variant = p.get("loadout")
	if lo is WeaponLoadout:
		(lo as WeaponLoadout).infinite_ammo = infinite_ammo


func set_god_mode(on: bool) -> void:
	god_mode = on
	_apply_player_flags()


func set_infinite_ammo(on: bool) -> void:
	infinite_ammo = on
	_apply_player_flags()


## Brouillard : désactivé = tout est révélé et la brume masquée.
func set_fog(on: bool) -> void:
	fog_enabled = on
	var fog := raid.fog
	if fog == null:
		return
	if fog.has_method("reveal_all"):
		fog.call("reveal_all", not on)
	fog.visible = on


# --- Râtelier -----------------------------------------------------------------------

## Prend l'arme `id` en main (emplacement courant ; l'ancienne est rangée, pas jetée).
func take_weapon(id: StringName) -> bool:
	var base := WeaponCatalog.get_weapon(id)
	var p := _player()
	if base == null or p == null or not p.has_method("equip_into_current_slot"):
		return false
	var old: Variant = p.call("equip_into_current_slot", base)
	if old is WeaponData and GameState.raid_inventory != null:
		GameState.raid_inventory.add_item(LootDB.weapon_item(old as WeaponData), 1)
	_apply_player_flags()
	return true


## Ajoute `n` objets `id` au sac de raid. Renvoie le nombre ajouté.
func take_item(id: StringName, n: int = 1) -> int:
	var it := LootDB.get_item(id)
	if it == null or GameState.raid_inventory == null:
		return 0
	return GameState.raid_inventory.add_item(it, n)


## Arme tenue (null si aucune).
func held_weapon() -> WeaponData:
	var p := _player()
	var lo: Variant = p.get("loadout") if p != null else null
	return (lo as WeaponLoadout).current_weapon() if lo is WeaponLoadout else null


## Skins applicables à l'arme tenue.
func skins_for_held() -> Array[SkinData]:
	var out: Array[SkinData] = []
	var w := held_weapon()
	if w == null:
		return out
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_WEAPON):
		if s.applies_to(w.category, w.id):
			out.append(s)
	return out


## Habille l'arme tenue avec le skin `skin_id` (vide = aucun). Affichage seulement : le profil
## (skins possédés, skins portés) n'est jamais modifié.
func apply_weapon_skin(skin_id: StringName) -> bool:
	var w := held_weapon()
	var p := _player()
	if w == null or p == null:
		return false
	var visual: Variant = p.get("visual")
	var wv: Variant = visual.get("weapon_view") if visual is Node else null
	if not (wv is WeaponView):
		return false
	var ids := {}
	if skin_id != &"":
		ids[String(w.id)] = String(skin_id)
	(wv as WeaponView).set_skin_ids(ids)
	return true


# --- Ennemis à la demande --------------------------------------------------------------

## Archétypes proposés : [{name, kind}] ([test_arena] archetypes, dans l'ordre).
static func archetypes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d: Variant = Balance.get_value("test_arena", "archetypes", {})
	if d is Dictionary:
		for k: Variant in d:
			out.append({"name": String(k), "kind": StringName(str(d[k]))})
	return out


## Fait apparaître `count` ennemis du kind donné dans la zone du haut. Renvoie les ennemis créés.
func spawn_enemy(kind: StringName, count: int = 1) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var data := Raid.load_enemy_data(kind)
	for i: int in maxi(count, 1):
		_spawn_count += 1
		var f := Vector2(ENEMY_ZONE.position.x + ENEMY_ZONE.size.x * fposmod(_spawn_count * 0.37, 1.0),
			ENEMY_ZONE.position.y + ENEMY_ZONE.size.y * fposmod(_spawn_count * 0.61, 1.0))
		var e := raid._add_enemy(data, _world_at(f), "Arena_%s_%d" % [String(kind).to_pascal_case(), _spawn_count])
		if e != null:
			spawned.append(e)
			out.append(e)
	return out


func clear_enemies() -> void:
	for e: Node2D in spawned:
		if is_instance_valid(e):
			e.queue_free()
	spawned.clear()


# --- Remise à zéro, mort, sortie -------------------------------------------------------

## Remise à zéro : ennemis retirés, compteurs des mannequins vidés, joueur soigné et rechargé,
## sac vidé.
func reset() -> void:
	clear_enemies()
	for d: ArenaDummy in dummies:
		if is_instance_valid(d):
			d.reset_meter()
	var p := _player()
	if p != null:
		var mh: Variant = p.get("max_hp")
		if mh != null and p.has_method("heal"):
			p.call("heal", float(mh))
		var lo: Variant = p.get("loadout")
		if lo is WeaponLoadout and (lo as WeaponLoadout).has_method("refill_all"):
			(lo as WeaponLoadout).call("refill_all")
		if raid.layout != null:
			raid.place_player(raid.layout.player_spawn)
	if GameState.raid_inventory != null:
		GameState.raid_inventory.clear()


## Mort sans invincibilité : l'arène est relancée telle quelle (rien n'est perdu).
func on_player_died() -> void:
	var delay := Balance.get_float("test_arena", "reload_delay", 1.5)
	get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void:
		if is_inside_tree():
			get_tree().reload_current_scene())


## Sortie libre vers le menu (rien n'est perdu ni gagné).
func exit_to_menu() -> void:
	get_tree().paused = false
	GameState.raid_weapons = []
	GameState.raid_gadget = null
	GameState.raid_inventory = Inventory.from_balance()
	GameState.set_current_map(null)
	MenuKit.go_to(raid, MenuKit.MAIN_MENU_SCENE)
