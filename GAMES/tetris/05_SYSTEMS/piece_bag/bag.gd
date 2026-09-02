# bag.gd — ligne core.piece_bag (R1 Sac de 7).
# genre.tetris.seven_tetrominoes : chaque sac emet EXACTEMENT les 7 tetrominos {I,O,T,S,Z,J,L},
# multiplicite 1 par sac, aucune autre forme. Deterministe par graine (aucun alea non seede :
# melange Fisher-Yates pilote par un LCG). Ne connait ni la grille ni les collisions. RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Un sac : permutation deterministe des 7 types (entiers 0..PIECE_COUNT-1), fonction de la graine.
# L'ensemble rendu est TOUJOURS {0..6} exactement — la graine ne change que l'ORDRE.
static func generate_bag(seed_val: int) -> Array:
	var order: Array = []
	for k in range(P.PIECE_COUNT):
		order.append(k)
	var rng: int = _seed_normalise(seed_val)
	# Fisher-Yates ascendant->descendant par un for (jamais un compteur mutable : robuste au
	# mutant `-=`, et surtout deterministe). i parcourt PIECE_COUNT-1 .. 1.
	for i in range(P.PIECE_COUNT - 1, 0, -1):
		rng = _lcg(rng)
		var j: int = rng % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order

# Graine du sac SUIVANT (avance deterministe) : evite qu'un sac se repete a l'identique.
static func next_seed(seed_val: int) -> int:
	return _lcg(_seed_normalise(seed_val))

# LCG 31 bits (constantes glibc). Aucun operateur mutable de comparaison/booleen.
static func _lcg(x: int) -> int:
	return (x * 1103515245 + 12345) & 0x7fffffff

static func _seed_normalise(seed_val: int) -> int:
	return (seed_val & 0x7fffffff) + 1
