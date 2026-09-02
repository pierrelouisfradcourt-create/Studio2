# collision_exact.test.gd — ligne core.collision. Valeurs STRICTES vivant/mort sur les
# fixtures limites : 4 coins, murs, case du cou, case de queue liberee. Zero tolerance.
extends RefCounted

const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var n := P.TAILLE_GRILLE
	# Les 4 coins sont DANS la grille (strict false).
	h.eq(Collision.hors_grille(Vector2i(0, 0)), false, "coin (0,0) dans la grille")
	h.eq(Collision.hors_grille(Vector2i(n - 1, 0)), false, "coin haut-droit dans la grille")
	h.eq(Collision.hors_grille(Vector2i(0, n - 1)), false, "coin bas-gauche dans la grille")
	h.eq(Collision.hors_grille(Vector2i(n - 1, n - 1)), false, "coin bas-droit dans la grille")
	# Juste au-dela de chaque bord : strict true.
	h.eq(Collision.hors_grille(Vector2i(-1, 0)), true, "(-1,0) hors grille")
	h.eq(Collision.hors_grille(Vector2i(n, 0)), true, "(n,0) hors grille")
	h.eq(Collision.hors_grille(Vector2i(0, -1)), true, "(0,-1) hors grille")
	h.eq(Collision.hors_grille(Vector2i(0, n)), true, "(0,n) hors grille")
	h.eq(Collision.hors_grille(Vector2i(n, n)), true, "(n,n) hors grille")
	# Corps : appartenance stricte.
	var corps := [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	h.eq(Collision.sur_corps(Vector2i(4, 5), corps), true, "case du cou est sur le corps")
	h.eq(Collision.sur_corps(Vector2i(6, 5), corps), false, "case libre pas sur le corps")
	# La case de queue (3,5) EST sur le corps tant qu'on la teste telle quelle ;
	# c'est le loop qui la retire avant test quand elle se libere (voir tick_pure).
	h.eq(Collision.sur_corps(Vector2i(3, 5), corps), true, "case de queue presente = sur le corps")
	# Nourriture : egalite exacte.
	h.eq(Collision.sur_nourriture(Vector2i(7, 8), Vector2i(7, 8)), true, "tete sur nourriture")
	h.eq(Collision.sur_nourriture(Vector2i(7, 8), Vector2i(7, 9)), false, "tete a cote de nourriture")
