# brick_field.gd — ligne state.brick_field. Detient le mur de briques (Array[bool]) et le
# compte restant. Ne DECIDE d'aucune destruction (c'est brick_collision) : il l'APPLIQUE.
# RefCounted, pur. Capacite proposee hors registre : game.brick_field (gate Pierre, fog F5).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Index plat d'une brique (rangee, colonne) -> position dans l'Array[bool].
static func index(rangee: int, colonne: int) -> int:
	return rangee * P.GRILLE_COLONNES + colonne

# Rectangle geometrique (terrain) d'une brique, decale du start_y seede du niveau.
static func rect(rangee: int, colonne: int, start_y: float) -> Rect2:
	return Rect2(
		colonne * P.BRIQUE_LARGEUR,
		start_y + rangee * P.BRIQUE_HAUTEUR,
		P.BRIQUE_LARGEUR,
		P.BRIQUE_HAUTEUR)

static func est_presente(state, idx: int) -> bool:
	return idx >= 0 and idx < state.bricks.size() and state.bricks[idx]

# Detruit UNE brique presente (mute un state deja clone) : la retire et decremente le compte
# de EXACTEMENT 1. Renvoie true si une brique a bien ete retiree.
static func detruire(state, idx: int) -> bool:
	if not est_presente(state, idx):
		return false
	state.bricks[idx] = false
	state.briques_restantes -= 1
	return true
