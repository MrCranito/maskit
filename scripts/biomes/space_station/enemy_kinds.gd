extends RefCounted
## Visuels des ennemis de la Station spatiale (format EnemyVisual.KINDS), chargés par BiomeRegistry.
##
## Le bestiaire de la station (ss_security_droid, ss_spectre, ss_teleporter, ss_detector,
## ss_station_guardian, ss_alien, ss_alien_brood + élites et boss) utilise le mode « planches »
## d'EnemyArt : assets/sprites/enemies/<kind>/<kind>_frames.tres, rendus par
## art/blender/bestiary/space_station/build_ss_enemies.py. Aucun sprite unique n'est donc déclaré
## ici (les planches ont priorité dans EnemyVisual.setup).

const KINDS := {}
