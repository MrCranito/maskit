shader_type canvas_item;
render_mode blend_mul;
// Brouillard « naturel » ([fog] fog_style="natural") : comme le décor assombri (option A), le
// décor reste lisible hors vue, en version nuit désaturée ; mais rien n'est coupé net :
//   - bord du champ de vision large et irrégulier ([fog_natural] edge_feather_px, edge_softness) ;
//   - pénombre : au-delà du bord, la lumière décroît sur un large dégradé (halo du masque,
//     canal G, [fog_natural] halo_px) au lieu de tomber d'un coup ;
//   - la lumière faiblit avec la distance au joueur (vignettage qui commence tôt et doux) ;
//   - teinte nuit chaude-froide (pas d'aplat violet), légère brume animée.
// Passe 1 / 2 (multiplicative) : décor × F, sans lecture de l'écran (fog_natural_common).
// La passe 2 (fog_natural_add.gdshader, nœud enfant de FogOfWar) ajoute B. 4 lectures de texture
// par passe. Ennemis et conteneurs hors vue restent cachés par FogOfWar (groupe fog_hideable).

#include "res://assets/shaders/fog_natural_common.gdshaderinc"

void fragment() {
	vec3 f;
	vec3 b;
	natural_terms(world_pos, TIME, f, b);
	COLOR = vec4(f, 1.0);
}
