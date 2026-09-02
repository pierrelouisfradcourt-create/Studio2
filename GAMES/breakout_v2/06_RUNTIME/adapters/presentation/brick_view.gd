# brick_view.gd — ligne render.brick_destruction. Projette le champ de briques vers une liste
# de primitives : SEULES les briques encore presentes sont dessinees. Une brique detruite
# disparait du rendu au meme instant ou l'etat la retire (aucune structure parallele).
# LIT l'etat, ne decide d'aucune destruction. RefCounted, aucune API de rendu.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")

# Une brique visible par rangee dans un degrade lisible (couleur = rangee).
static func couleur_rangee(rangee: int) -> Color:
	var denom: int = P.GRILLE_RANGEES - 1
	var t: float = 0.0 if denom <= 0 else float(rangee) / float(denom)
	return Color(0.30 + 0.60 * t, 0.75 - 0.35 * t, 0.45 + 0.40 * (1.0 - t))

# Primitives des briques ENCORE PRESENTES (un petit liesere retire pour la lisibilite).
static func primitives(state) -> Array:
	var out: Array = []
	for rangee in range(P.GRILLE_RANGEES):
		for colonne in range(P.GRILLE_COLONNES):
			var idx := BrickField.index(rangee, colonne)
			if idx >= state.bricks.size() or not state.bricks[idx]:
				continue
			var r := BrickField.rect(rangee, colonne, state.start_y)
			out.append({
				"kind": "rect",
				"rect": Rect2(r.position.x + 1.0, r.position.y + 1.0, r.size.x - 2.0, r.size.y - 2.0),
				"color": couleur_rangee(rangee),
			})
	return out
