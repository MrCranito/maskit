extends Node
## Gestionnaire audio global (autoload « AudioManager », à enregistrer dans project.godot) :
##   AudioManager="*res://scripts/core/audio_manager.gd"
##
## Usage :
##   AudioManager.play_sfx(&"revolver_shot")                  # son non positionné (UI…)
##   AudioManager.play_sfx(&"golem_stomp", global_position)   # son 2D positionné
##   AudioManager.play_music(&"western_explore")
##
## Un nom peut correspondre à plusieurs variantes : une est tirée au hasard,
## avec une légère variation de hauteur pour éviter la répétition.
## Les sons et musiques sont des assets tiers (voir CREDITS.md).

const SFX_POOL_SIZE: int = 12
const SFX_2D_POOL_SIZE: int = 24
const PITCH_JITTER: float = 0.06
const MUSIC_FADE_TIME: float = 0.8

## Nom logique -> liste de variantes (.ogg).
const SFX: Dictionary = {
	&"revolver_shot": [
		"res://assets/audio/sfx/weapons/revolver_shot_1.ogg",
		"res://assets/audio/sfx/weapons/revolver_shot_2.ogg",
		"res://assets/audio/sfx/weapons/revolver_shot_3.ogg",
	],
	&"rifle_shot": ["res://assets/audio/sfx/weapons/rifle_shot.ogg"],
	&"pistol_shot_light": ["res://assets/audio/sfx/weapons/pistol_shot_light.ogg"],
	&"shotgun_blast": ["res://assets/audio/sfx/weapons/shotgun_blast.ogg"],
	&"gun_shot_alt": ["res://assets/audio/sfx/weapons/gun_shot_alt.ogg"],
	&"bow_shot": ["res://assets/audio/sfx/weapons/bow_shot.ogg"],
	&"reload": ["res://assets/audio/sfx/weapons/reload.ogg"],
	&"dry_fire": ["res://assets/audio/sfx/weapons/dry_fire.ogg"],
	&"blade_swing": [
		"res://assets/audio/sfx/weapons/blade_swing_1.ogg",
		"res://assets/audio/sfx/weapons/blade_swing_2.ogg",
		"res://assets/audio/sfx/weapons/blade_swing_3.ogg",
	],
	&"blade_swing_heavy": ["res://assets/audio/sfx/weapons/blade_swing_heavy.ogg"],
	&"blade_clash": ["res://assets/audio/sfx/weapons/blade_clash.ogg"],
	&"explosion": [
		"res://assets/audio/sfx/weapons/explosion_1.ogg",
		"res://assets/audio/sfx/weapons/explosion_2.ogg",
		"res://assets/audio/sfx/weapons/explosion_3.ogg",
	],
	&"flame": ["res://assets/audio/sfx/weapons/flame.ogg"],
	&"weapon_switch": ["res://assets/audio/sfx/weapons/weapon_switch.ogg"],
	&"bullet_impact": [
		"res://assets/audio/sfx/impacts/bullet_impact_1.ogg",
		"res://assets/audio/sfx/impacts/bullet_impact_2.ogg",
	],
	&"hit_flesh": ["res://assets/audio/sfx/impacts/hit_flesh.ogg"],
	&"hit_heavy": ["res://assets/audio/sfx/impacts/hit_heavy.ogg"],
	&"projectile_destroy": ["res://assets/audio/sfx/impacts/projectile_destroy.ogg"],
	&"metal_impact": ["res://assets/audio/sfx/impacts/metal_impact.ogg"],
	&"wood_break": ["res://assets/audio/sfx/impacts/wood_break.ogg"],
	&"glass_break": [
		"res://assets/audio/sfx/impacts/glass_break_1.ogg",
		"res://assets/audio/sfx/impacts/glass_break_2.ogg",
	],
	&"glass_hit": ["res://assets/audio/sfx/impacts/glass_hit.ogg"],
	&"step_sand": ["res://assets/audio/sfx/movement/step_sand.ogg"],
	&"steps_loop": ["res://assets/audio/sfx/movement/steps_loop.ogg"],
	&"land": ["res://assets/audio/sfx/movement/land.ogg"],
	&"dash": ["res://assets/audio/sfx/movement/dash.ogg"],
	&"jump": ["res://assets/audio/sfx/movement/jump.ogg"],
	&"door_open": ["res://assets/audio/sfx/doors/door_open.ogg"],
	&"door_close": ["res://assets/audio/sfx/doors/door_close.ogg"],
	&"door_locked": ["res://assets/audio/sfx/doors/door_locked.ogg"],
	&"door_unlock": ["res://assets/audio/sfx/doors/door_unlock.ogg"],
	&"coin_pickup": ["res://assets/audio/sfx/loot/coin_pickup.ogg"],
	&"gold_pickup": ["res://assets/audio/sfx/loot/gold_pickup.ogg"],
	&"item_pickup": ["res://assets/audio/sfx/loot/item_pickup.ogg"],
	&"ammo_pickup": ["res://assets/audio/sfx/loot/ammo_pickup.ogg"],
	&"container_search": [
		"res://assets/audio/sfx/loot/container_search_1.ogg",
		"res://assets/audio/sfx/loot/container_search_2.ogg",
	],
	&"container_open": ["res://assets/audio/sfx/loot/container_open.ogg"],
	&"rare_reveal": ["res://assets/audio/sfx/loot/rare_reveal.ogg"],
	&"key_pickup": ["res://assets/audio/sfx/loot/key_pickup.ogg"],
	&"item_equip": ["res://assets/audio/sfx/loot/item_equip.ogg"],
	&"outlaw_death": [
		"res://assets/audio/sfx/enemies/outlaw_death_1.ogg",
		"res://assets/audio/sfx/enemies/outlaw_death_2.ogg",
		"res://assets/audio/sfx/enemies/outlaw_death_3.ogg",
	],
	&"outlaw_hurt": [
		"res://assets/audio/sfx/enemies/outlaw_hurt_1.ogg",
		"res://assets/audio/sfx/enemies/outlaw_hurt_2.ogg",
		"res://assets/audio/sfx/enemies/outlaw_hurt_3.ogg",
	],
	&"enemy_death_generic": ["res://assets/audio/sfx/enemies/enemy_death_generic.ogg"],
	&"enemy_destroy": ["res://assets/audio/sfx/enemies/enemy_destroy.ogg"],
	&"enemy_attack": ["res://assets/audio/sfx/enemies/enemy_attack.ogg"],
	&"golem_growl": [
		"res://assets/audio/sfx/enemies/golem_growl_1.ogg",
		"res://assets/audio/sfx/enemies/golem_growl_2.ogg",
	],
	&"golem_stomp": ["res://assets/audio/sfx/enemies/golem_stomp.ogg"],
	&"golem_crumble": ["res://assets/audio/sfx/enemies/golem_crumble.ogg"],
	&"enemy_alert": ["res://assets/audio/sfx/alerts/enemy_alert.ogg"],
	&"danger_jingle": ["res://assets/audio/sfx/alerts/danger_jingle.ogg"],
	&"player_hurt": ["res://assets/audio/sfx/player/player_hurt.ogg"],
	&"player_death": ["res://assets/audio/sfx/player/player_death.ogg"],
	&"heal": ["res://assets/audio/sfx/player/heal.ogg"],
	&"power_up": ["res://assets/audio/sfx/player/power_up.ogg"],
	&"mask_power": ["res://assets/audio/sfx/player/mask_power.ogg"],
	&"extraction_success": ["res://assets/audio/sfx/player/extraction_success.ogg"],
	&"extraction_fail": ["res://assets/audio/sfx/player/extraction_fail.ogg"],
	&"click": ["res://assets/audio/sfx/ui/click.ogg"],
	&"click_soft": ["res://assets/audio/sfx/ui/click_soft.ogg"],
	&"hover": ["res://assets/audio/sfx/ui/hover.ogg"],
	&"confirm": ["res://assets/audio/sfx/ui/confirm.ogg"],
	&"confirm_big": ["res://assets/audio/sfx/ui/confirm_big.ogg"],
	&"back": ["res://assets/audio/sfx/ui/back.ogg"],
	&"error": ["res://assets/audio/sfx/ui/error.ogg"],
	&"panel_open": ["res://assets/audio/sfx/ui/panel_open.ogg"],
	&"panel_close": ["res://assets/audio/sfx/ui/panel_close.ogg"],
	&"toggle": ["res://assets/audio/sfx/ui/toggle.ogg"],
	&"tick": ["res://assets/audio/sfx/ui/tick.ogg"],
	&"coin_spend": ["res://assets/audio/sfx/ui/coin_spend.ogg"],
	&"desert_wind": ["res://assets/audio/sfx/ambience/desert_wind.ogg"],
	&"raven": ["res://assets/audio/sfx/ambience/raven.ogg"],
	&"cattle": ["res://assets/audio/sfx/ambience/cattle.ogg"],
}

## Musiques (import loop=true dans les .import).
const MUSIC: Dictionary = {
	&"western_hub": "res://assets/audio/music/western_hub.ogg",
	&"western_explore": "res://assets/audio/music/western_explore.ogg",
	&"western_combat": "res://assets/audio/music/western_combat.ogg",
}

## Volume global (linéaire 0..1) appliqué aux lecteurs gérés par ce nœud.
var master_volume: float = 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		_apply_volumes()
var sfx_volume: float = 1.0:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		_apply_volumes()
var music_volume: float = 0.7:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		_apply_volumes()

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_2d_players: Array[AudioStreamPlayer2D] = []
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i: int in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	for i: int in SFX_2D_POOL_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.max_distance = 1400.0
		add_child(p2)
		_sfx_2d_players.append(p2)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_apply_volumes()


## Joue un effet sonore. position = Vector2.INF -> son non positionné.
## Retourne false si le nom est inconnu ou le fichier introuvable.
func play_sfx(sfx_name: StringName, position: Vector2 = Vector2.INF, volume_db: float = 0.0) -> bool:
	var stream := _pick_stream(sfx_name)
	if stream == null:
		return false
	var pitch := 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	var db := volume_db + linear_to_db(maxf(master_volume * sfx_volume, 0.0001))
	if position == Vector2.INF:
		var p := _free_player(_sfx_players) as AudioStreamPlayer
		p.stream = stream
		p.pitch_scale = pitch
		p.volume_db = db
		p.play()
	else:
		var p2 := _free_player(_sfx_2d_players) as AudioStreamPlayer2D
		p2.stream = stream
		p2.pitch_scale = pitch
		p2.volume_db = db
		p2.global_position = position
		p2.play()
	return true


## Lance une musique (en boucle). Ne fait rien si elle joue déjà.
func play_music(music_name: StringName, fade: bool = true) -> bool:
	if music_name == _current_music and _music_player.playing:
		return true
	if not MUSIC.has(music_name):
		push_warning("AudioManager : musique inconnue '%s'" % music_name)
		return false
	var stream := _load(MUSIC[music_name])
	if stream == null:
		return false
	_current_music = music_name
	var target_db := linear_to_db(maxf(master_volume * music_volume, 0.0001))
	_music_player.stream = stream
	if fade:
		_music_player.volume_db = -40.0
		_music_player.play()
		create_tween().tween_property(_music_player, "volume_db", target_db, MUSIC_FADE_TIME)
	else:
		_music_player.volume_db = target_db
		_music_player.play()
	return true


func stop_music(fade: bool = true) -> void:
	_current_music = &""
	if not fade:
		_music_player.stop()
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -40.0, MUSIC_FADE_TIME)
	tw.tween_callback(_music_player.stop)


func has_sfx(sfx_name: StringName) -> bool:
	return SFX.has(sfx_name)


## Liste de tous les chemins référencés (utilisé par les tests).
static func all_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in SFX:
		for path: String in SFX[key]:
			out.append(path)
	for key: StringName in MUSIC:
		out.append(MUSIC[key])
	return out


func _pick_stream(sfx_name: StringName) -> AudioStream:
	if not SFX.has(sfx_name):
		push_warning("AudioManager : son inconnu '%s'" % sfx_name)
		return null
	var variants: Array = SFX[sfx_name]
	return _load(variants[_rng.randi() % variants.size()])


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager : impossible de charger %s" % path)
		return null
	_cache[path] = stream
	return stream


## Renvoie un lecteur libre, ou le plus ancien (le premier) si tous jouent.
func _free_player(pool: Array) -> Node:
	for p: Node in pool:
		if not p.playing:
			return p
	var oldest: Node = pool.pop_front()
	pool.push_back(oldest)
	return oldest


func _apply_volumes() -> void:
	if _music_player != null and _music_player.playing:
		_music_player.volume_db = linear_to_db(maxf(master_volume * music_volume, 0.0001))
