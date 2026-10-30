extends RefCounted
## Compétences propres au bestiaire du monde « egypt » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier).

const DIR := "res://scripts/enemies/skills/egypt/"

const REGISTRY := {
	# Frappes au sol différées (une classe, plusieurs ids).
	&"eg_spike_trap": DIR + "eg_glyph_strike_skill.gd",
	&"eg_arrow_rain": DIR + "eg_glyph_strike_skill.gd",
	&"eg_sun_flare": DIR + "eg_glyph_strike_skill.gd",
	&"eg_curse": DIR + "eg_glyph_strike_skill.gd",
	&"eg_venom_spit": DIR + "eg_glyph_strike_skill.gd",
	&"eg_burrow": DIR + "eg_burrow_skill.gd",
	&"eg_temple_call": DIR + "eg_temple_call_skill.gd",
	&"eg_raise_dead": DIR + "eg_raise_dead_skill.gd",
	&"eg_undying": DIR + "eg_undying_skill.gd",
	&"eg_bandage_lash": DIR + "eg_bandage_lash_skill.gd",
	&"eg_venom": DIR + "eg_venom_skill.gd",
	&"eg_sandstorm": DIR + "eg_sandstorm_skill.gd",
	&"eg_shadow_veil": DIR + "eg_shadow_veil_skill.gd",
	&"eg_solar_blessing": DIR + "eg_solar_blessing_skill.gd",
	&"eg_sun_rays": DIR + "eg_sun_rays_skill.gd",
}
