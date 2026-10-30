extends RefCounted
## Compétences propres au bestiaire du monde « carnival » (fusionnées par EnemySkills.registry()).
## id → chemin complet du script (une classe EnemySkill par fichier, dans ce dossier).
## Valeurs par défaut : balance.cfg [bestiary_carnival] (cv_balance.gd).

const DIR := "res://scripts/enemies/skills/carnival/"

const REGISTRY := {
	&"cv_racket": DIR + "cv_racket_skill.gd",
	&"cv_balloon": DIR + "cv_balloon_skill.gd",
	&"cv_vault": DIR + "cv_vault_skill.gd",
	&"cv_shade": DIR + "cv_shade_skill.gd",
	&"cv_ambush": DIR + "cv_ambush_skill.gd",
	&"cv_call": DIR + "cv_call_skill.gd",
	&"cv_waltz": DIR + "cv_waltz_skill.gd",
	# Élites
	&"cv_rally": DIR + "cv_rally_skill.gd",
	&"cv_rallied": DIR + "cv_rallied_skill.gd",
	&"cv_fire_ring": DIR + "cv_fire_ring_skill.gd",
	# Boss
	&"cv_juggle": DIR + "cv_juggle_skill.gd",
	&"cv_fair_traps": DIR + "cv_fair_traps_skill.gd",
	&"cv_fireworks": DIR + "cv_fireworks_skill.gd",
}
