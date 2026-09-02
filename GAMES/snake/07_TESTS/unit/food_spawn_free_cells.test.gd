# food_spawn_free_cells.test.gd — ligne core.food_spawn. La nourriture ne coincide
# JAMAIS avec le corps ; sur 1 case libre le tirage la retourne ; sur 0 case libre il
# renvoie l'etat de grille pleine sans boucler ; deterministe (meme graine -> meme case).
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Food = preload("res://05_SYSTEMS/food_spawn/food_spawn.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Nombre de cases libres = total - segments.
	var s = State.initial(2)
	var total := P.TAILLE_GRILLE * P.TAILLE_GRILLE
	h.eq(Food.cases_libres(s).size(), total - s.segments.size(), "cases libres = total - segments")

	# La nourriture initiale n'est jamais sous le corps.
	h.ok(not (s.nourriture in s.segments), "nourriture initiale hors du corps")

	# Sur un run reel, la nourriture reste toujours hors du corps a chaque spawn.
	var cur = s
	var sous_corps := 0
	for i in range(60):
		cur = Loop.step(cur, Loop.AUCUNE)["etat"]
		if cur.statut != State.Statut.EN_COURS:
			cur = State.initial(i + 3)
		if cur.nourriture in cur.segments:
			sous_corps += 1
	h.eq(sous_corps, 0, "0 nourriture sous le corps sur 60 ticks")

	# Determinisme : meme etat -> meme tirage.
	var a = State.initial(2)
	var t1 = Food.tirer(a)
	var t2 = Food.tirer(a)
	h.eq(t1["cellule"], t2["cellule"], "meme etat -> meme cellule tiree")
	h.eq(t1["rng_state"], t2["rng_state"], "meme etat -> meme rng_state")

	# UNE seule case libre : le tirage retourne CETTE case, en un nombre borne d'operations.
	var un = State.initial(2)
	var libre := Vector2i(0, 0)
	un.segments = []
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			var c := Vector2i(x, y)
			if c != libre:
				un.segments.append(c)
	un.longueur = un.segments.size()
	var t := Food.tirer(un)
	h.eq(t["grille_pleine"], false, "1 case libre -> pas grille pleine")
	h.eq(t["cellule"], libre, "1 case libre -> tirage retourne cette case")

	# ZERO case libre : etat terminal de grille pleine, sans boucler.
	var plein = State.initial(2)
	plein.segments = []
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			plein.segments.append(Vector2i(x, y))
	plein.longueur = plein.segments.size()
	var tp := Food.tirer(plein)
	h.eq(tp["grille_pleine"], true, "0 case libre -> grille pleine signalee (sans boucle infinie)")
