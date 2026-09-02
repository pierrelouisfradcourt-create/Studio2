# field_view.gd — ligne render.field_visible. Projette l'etat vers une liste de PRIMITIVES a
# dessiner (terrain, raquette, balle) : LIT l'etat, ne decide d'AUCUNE regle. Le pilote de
# scene (main.gd) fait le dessin reel ; ce module n'appelle aucune API de rendu. RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

const COULEUR_FOND := Color(0.05, 0.06, 0.12)
const COULEUR_RAQUETTE := Color(0.90, 0.92, 0.98)
const COULEUR_BALLE := Color(1.0, 0.95, 0.4)

# Liste de primitives {kind, ...} decrivant le terrain, la raquette et la balle a cet etat.
static func primitives(state) -> Array:
	var out: Array = []
	out.append({"kind": "rect", "rect": Rect2(0.0, 0.0, P.TERRAIN_LARGEUR, P.TERRAIN_HAUTEUR), "color": COULEUR_FOND})
	var hw: float = P.raquette_demi_largeur()
	out.append({
		"kind": "rect",
		"rect": Rect2(state.paddle_x - hw, P.raquette_y(), P.RAQUETTE_LARGEUR, P.RAQUETTE_HAUTEUR),
		"color": COULEUR_RAQUETTE,
	})
	out.append({"kind": "circle", "center": state.ball_pos, "radius": P.BALLE_RAYON, "color": COULEUR_BALLE})
	return out
