# test_piece_bag.gd — R1 Sac de 7. Assert STRICT : chaque sac emet EXACTEMENT {I,O,T,S,Z,J,L}
# (types 0..6), multiplicite 1 par sac, aucune autre forme. Deterministe par graine.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Bag = preload("res://05_SYSTEMS/piece_bag/bag.gd")

func run(h) -> void:
	for seed in [1, 2, 7, 42, 100]:
		var bag: Array = Bag.generate_bag(seed)
		h.eq(bag.size(), P.PIECE_COUNT, "taille 7 (graine %d)" % seed)
		var tri: Array = bag.duplicate()
		tri.sort()
		h.eq(tri, [0, 1, 2, 3, 4, 5, 6], "ensemble == {0..6} (graine %d)" % seed)
		for t in range(P.PIECE_COUNT):
			h.eq(bag.count(t), 1, "type %d present une seule fois (graine %d)" % [t, seed])
	# Determinisme strict : meme graine -> meme sac.
	h.eq(Bag.generate_bag(1), Bag.generate_bag(1), "deterministe par graine")
	# La graine suivante avance (sacs successifs non identiques a l'infini).
	h.ok(Bag.next_seed(1) != 1, "next_seed avance la graine")
