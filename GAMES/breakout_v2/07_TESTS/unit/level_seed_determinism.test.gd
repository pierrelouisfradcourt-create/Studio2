# level_seed_determinism.test.gd — ligne level.seeded_generation. Meme (seed, niveau) ->
# disposition STRICTEMENT identique ; seeds distinctes -> dispositions distinctes (VARIANCE
# PROUVEE) ; compte CONSTANT = rangees*colonnes, toutes presentes.
extends RefCounted

const Level = preload("res://05_SYSTEMS/level_gen/level_gen.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# --- determinisme : meme (seed, niveau) -> meme disposition (bricks + start_y) ---
	var a: Dictionary = Level.generer(3, 0)
	var b: Dictionary = Level.generer(3, 0)
	h.eq(a["start_y"], b["start_y"], "determinisme: meme seed -> meme start_y")
	h.eq(a["bricks"], b["bricks"], "determinisme: meme seed -> memes briques")

	# --- compte CONSTANT, toutes presentes ---
	h.eq(a["bricks"].size(), P.total_briques(), "compte = rangees*colonnes")
	var toutes := true
	for present in a["bricks"]:
		if not present:
			toutes = false
	h.eq(toutes, true, "toutes les briques presentes a la generation")

	# --- VARIANCE : les offsets seedes couvrent LEVEL_NB_OFFSETS valeurs distinctes ---
	var vus := {}
	for sd in range(P.LEVEL_NB_OFFSETS):
		vus[Level.start_y(sd, 0)] = true
	h.eq(vus.size(), P.LEVEL_NB_OFFSETS, "offsets seedes distincts (variance prouvee, >=2)")
	# deux seeds concretes distinctes -> deux start_y distincts.
	h.ok(Level.start_y(1, 0) != Level.start_y(2, 0), "seed 1 != seed 2 -> dispositions distinctes")

	# --- compte identique quelle que soit la seed (seule la position varie) ---
	h.eq(Level.generer(1, 0)["bricks"].size(), Level.generer(2, 0)["bricks"].size(), "compte invariant a la seed")
