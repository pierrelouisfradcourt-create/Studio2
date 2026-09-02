# grid_categories.test.gd — ligne render.grid. Les 4 categories visuelles (mur, tete,
# corps, nourriture) ne partagent AUCUNE couleur (0 paire en collision) et la categorisation
# d'une cellule est STRICTE. Testable en headless (pas de rendu, juste la projection pure).
extends RefCounted

const GV = preload("res://06_RUNTIME/adapters/presentation/grid_view.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# EXACTEMENT 0 paire de categories jouables partageant la meme couleur.
	h.eq(GV.categories_couleur_partagee(), 0, "0 categorie de gameplay a couleur partagee")
	# Categorisation STRICTE sur un etat pose a la main.
	var s = State.initial(5)
	s.segments = [Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4)]
	s.longueur = 3
	s.nourriture = Vector2i(8, 8)
	h.eq(GV.categorie_cellule(s, Vector2i(4, 4)), GV.Cat.TETE, "tete categorisee TETE")
	h.eq(GV.categorie_cellule(s, Vector2i(3, 4)), GV.Cat.CORPS, "corps categorise CORPS")
	h.eq(GV.categorie_cellule(s, Vector2i(8, 8)), GV.Cat.NOURRITURE, "nourriture categorisee NOURRITURE")
	h.eq(GV.categorie_cellule(s, Vector2i(-1, 4)), GV.Cat.MUR, "hors grille categorise MUR")
	h.eq(GV.categorie_cellule(s, Vector2i(0, 0)), GV.Cat.VIDE, "case libre categorisee VIDE")
