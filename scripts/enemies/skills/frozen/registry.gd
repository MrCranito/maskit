extends RefCounted
## Compétences propres au bestiaire du monde « frozen » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier).
## Nœuds de danger associés (non déclarés ici) : ice_storm.gd, ice_bolt.gd, ice_shards.gd.

const DIR := "res://scripts/enemies/skills/frozen/"

const REGISTRY := {
	&"ice_pack_hunter": DIR + "ice_pack_hunter_skill.gd",
	&"ice_chill": DIR + "ice_chill_skill.gd",
	&"ice_burrow": DIR + "ice_burrow_skill.gd",
	&"ice_ambush": DIR + "ice_ambush_skill.gd",
	&"ice_storm": DIR + "ice_storm_skill.gd",
	&"ice_frost_nova": DIR + "ice_frost_nova_skill.gd",
	&"ice_reform": DIR + "ice_reform_skill.gd",
	&"ice_cryo_shot": DIR + "ice_cryo_shot_skill.gd",
	&"ice_lab_call": DIR + "ice_lab_call_skill.gd",
	# Élites et boss
	&"ice_spikes": DIR + "ice_spikes_skill.gd",
	&"ice_icefall": DIR + "ice_icefall_skill.gd",
	&"ice_repair": DIR + "ice_repair_skill.gd",
}
