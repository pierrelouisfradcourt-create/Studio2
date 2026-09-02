# score_per_brick.test.gd — ligne state.score. Score = briques_detruites * points_par_brique,
# fonction PURE ; aucun increment sans destruction dans le meme tick.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Score = preload("res://05_SYSTEMS/game_state/score.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Fonction directe.
	h.eq(Score.depuis_detruites(0), 0, "0 brique -> score 0")
	h.eq(Score.depuis_detruites(1), P.POINTS_PAR_BRIQUE, "1 brique -> points_par_brique")
	h.eq(Score.depuis_detruites(7), 7 * P.POINTS_PAR_BRIQUE, "7 briques -> 7 * points_par_brique")

	# Recalcul depuis l'etat : aucune destruction -> score 0.
	var s = State.initial(1)
	h.eq(Score.recalculer(s), 0, "aucune destruction -> score 0")

	# Detruire 3 briques -> score = 3 * points.
	BrickField.detruire(s, 0)
	BrickField.detruire(s, 1)
	BrickField.detruire(s, 2)
	h.eq(Score.recalculer(s), 3 * P.POINTS_PAR_BRIQUE, "3 briques detruites -> 3 * points")
	# Le score suit le compte reel, jamais un increment aveugle.
	h.eq(Score.recalculer(s), (P.total_briques() - s.briques_restantes) * P.POINTS_PAR_BRIQUE, "score = detruites * points (fonction du compte reel)")
