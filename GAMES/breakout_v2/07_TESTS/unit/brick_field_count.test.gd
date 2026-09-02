# brick_field_count.test.gd — ligne state.brick_field. Compte initial = rangees*colonnes ;
# decroit de EXACTEMENT 1 par destruction ; jamais de destruction en chaine ni de retour arriere.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Index plat.
	h.eq(BrickField.index(0, 0), 0, "index(0,0) = 0")
	h.eq(BrickField.index(2, 3), 2 * P.GRILLE_COLONNES + 3, "index(r,c) = r*COLS + c")

	var s = State.initial(1)
	h.eq(s.briques_restantes, P.total_briques(), "compte initial = rangees*colonnes")
	h.eq(s.compter_briques(), P.total_briques(), "compte reel = rangees*colonnes")

	# Destruction d'une brique : -1 exact, retourne true.
	h.ok(BrickField.est_presente(s, 5), "brique 5 presente au depart")
	var avant: int = s.briques_restantes
	h.ok(BrickField.detruire(s, 5), "detruire(5) reussit")
	h.eq(s.briques_restantes, avant - 1, "compte decroit de EXACTEMENT 1")
	h.eq(s.compter_briques(), avant - 1, "compte reel coherent apres destruction")
	h.eq(BrickField.est_presente(s, 5), false, "brique 5 absente apres destruction")

	# Detruire une brique deja detruite : false, aucun double decrement (pas de retour arriere).
	h.eq(BrickField.detruire(s, 5), false, "detruire une brique absente -> false")
	h.eq(s.briques_restantes, avant - 1, "compte inchange (0 double decrement)")
