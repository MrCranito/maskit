extends RefCounted
## Compétences propres au bestiaire du monde « mall » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier).

const DIR := "res://scripts/enemies/skills/mall/"

const REGISTRY := {
	&"mall_pounce": DIR + "mall_pounce_skill.gd",
	&"mall_alarm": DIR + "mall_alarm_skill.gd",
	&"mall_illusion": DIR + "mall_illusion_skill.gd",
	&"mall_illusion_body": DIR + "mall_illusion_body_skill.gd",
	&"mall_shadow_step": DIR + "mall_shadow_step_skill.gd",
	&"mall_shadow_skin": DIR + "mall_shadow_skin_skill.gd",
	&"mall_cloak": DIR + "mall_cloak_skill.gd",
	&"mall_panic_wave": DIR + "mall_panic_wave_skill.gd",
	&"mall_overload": DIR + "mall_overload_skill.gd",
}
