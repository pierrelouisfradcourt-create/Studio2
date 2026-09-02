# test_scoring.gd — bareme superlineaire. Chaque palier pinne strictement ; 0/negatif -> 0 ;
# recompense par ligne d'un quadruple STRICTEMENT superieure a celle d'un simple.
extends RefCounted

const Scoring = preload("res://05_SYSTEMS/scoring/scoring.gd")

func run(h) -> void:
	h.eq(Scoring.score_for(0), 0, "0 ligne -> 0")
	h.eq(Scoring.score_for(1), 100, "1 ligne -> 100")
	h.eq(Scoring.score_for(2), 300, "2 lignes -> 300")
	h.eq(Scoring.score_for(3), 500, "3 lignes -> 500")
	h.eq(Scoring.score_for(4), 800, "4 lignes -> 800")
	h.eq(Scoring.score_for(-1), 0, "negatif -> 0")
	h.ok(float(Scoring.score_for(4)) / 4.0 > float(Scoring.score_for(1)), "quad par ligne > simple (superlineaire)")
