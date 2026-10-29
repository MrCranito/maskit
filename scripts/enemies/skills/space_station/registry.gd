extends RefCounted
## Compétences propres au bestiaire du monde « space_station » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier).

const DIR := "res://scripts/enemies/skills/space_station/"

const REGISTRY := {
	&"ss_blink_strike": DIR + "ss_blink_strike_skill.gd",
	&"ss_alarm_scan": DIR + "ss_alarm_scan_skill.gd",
	&"ss_zone_barrage": DIR + "ss_zone_barrage_skill.gd",
	&"ss_drone_launch": DIR + "ss_summon_skill.gd",
	&"ss_brood_summon": DIR + "ss_summon_skill.gd",
	&"ss_frenzy": DIR + "ss_frenzy_skill.gd",
}
