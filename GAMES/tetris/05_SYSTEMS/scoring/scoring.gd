# scoring.gd — ligne core.scoring. genre.tetris.superlinear_multi_clear_reward.
# Convertit un NOMBRE de lignes simultanees en points (bareme superlineaire du bloc params).
# Contrainte d'architecture : le scoring recoit un nombre, JAMAIS la grille — il ne connait pas
# le terrain. RefCounted (logique pure).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Points pour n lignes nettoyees d'un seul coup. 0 ligne -> 0 point. Le bareme est superlineaire :
# un quadruple (800) rapporte plus PAR LIGNE (200) qu'un simple (100).
static func score_for(n_lines: int) -> int:
	if n_lines <= 0:
		return 0
	if n_lines == 1:
		return P.SCORE_SIMPLE
	if n_lines == 2:
		return P.SCORE_DOUBLE
	if n_lines == 3:
		return P.SCORE_TRIPLE
	return P.SCORE_QUAD
