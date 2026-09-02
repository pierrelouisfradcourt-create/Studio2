# test_params.gd — bloc de parametres + table des formes. Assertions STRICTES (jamais >=).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	h.eq(P.COLS, 10, "puits large de 10")
	h.eq(P.ROWS, 20, "puits haut de 20")
	h.eq(P.PIECE_COUNT, 7, "exactement 7 tetrominos")
	h.eq(P.SPAWN, Vector2i(3, 0), "origine de spawn")
	h.eq(P.GRAVITY_PERIOD, 30, "periode de gravite")
	# Bareme superlineaire.
	h.eq(P.SCORE_SIMPLE, 100, "simple = 100")
	h.eq(P.SCORE_DOUBLE, 300, "double = 300")
	h.eq(P.SCORE_TRIPLE, 500, "triple = 500")
	h.eq(P.SCORE_QUAD, 800, "quad = 800")
	h.ok(float(P.SCORE_QUAD) / 4.0 > float(P.SCORE_SIMPLE), "quad par ligne (200) > simple (100)")
	# Couleurs / marqueurs de type.
	h.eq(P.color_of(0), 1, "color_of(0)=1")
	h.eq(P.color_of(6), 7, "color_of(6)=7")
	# Table des formes : 7 types x 4 orientations x 4 cellules.
	for t in range(P.PIECE_COUNT):
		for r in range(4):
			h.eq(P.shape(t, r).size(), 4, "type %d rot %d = 4 cellules" % [t, r])
