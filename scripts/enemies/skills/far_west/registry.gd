extends RefCounted
## Compétences propres au bestiaire du monde « far_west » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier ; quelques ids
## réutilisent une classe commune avec d'autres paramètres dans le .tres).

const REGISTRY := {
	# Classiques
	&"fw_alarm_bark": "res://scripts/enemies/skills/far_west/alarm_bark_skill.gd",
	&"fw_pack_hunter": "res://scripts/enemies/skills/far_west/pack_hunter_skill.gd",
	&"fw_pack_howl": "res://scripts/enemies/skills/far_west/pack_howl_skill.gd",
	&"fw_bodyguard": "res://scripts/enemies/skills/far_west/bodyguard_skill.gd",
	# Élites : Le Buffle (projection de débris = éventail de projectiles commun)
	&"fw_debris_throw": "res://scripts/enemies/skills/projectile_skill.gd",
	# Boss : Le Shérif Sable-Fou
	&"fw_revolver_shot": "res://scripts/enemies/skills/projectile_skill.gd",
	&"fw_double_shot": "res://scripts/enemies/skills/projectile_skill.gd",
	&"fw_sand_tornado": "res://scripts/enemies/skills/far_west/sand_tornado_skill.gd",
	&"fw_sheriff_charge": "res://scripts/enemies/skills/far_west/sheriff_charge_skill.gd",
	&"fw_call_outlaws": "res://scripts/enemies/skills/whistle_skill.gd",
}
