# rng_seeded_stream.test.gd — ligne rng.seeded_stream, capacite F3.
# L'etat du generateur est un CHAMP de l'etat de partie : deux executions de meme graine
# le portent identique, tick par tick.
extends RefCounted

const Rng = preload("res://05_SYSTEMS/rng/rng.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	# Suite reproductible : meme etat de depart -> meme suite, exactement.
	var a: int = Rng.graine(42)
	var b: int = Rng.graine(42)
	for _i in range(20):
		a = Rng.suivant(a)
		b = Rng.suivant(b)
	h.eq(a, b, "rng: meme graine, meme suite apres 20 crans")

	# Deux graines differentes produisent une suite differente : une suite constante
	# satisferait la reproductibilite sans rien generer.
	var c: int = Rng.graine(43)
	for _i in range(20):
		c = Rng.suivant(c)
	h.ok(a != c, "rng: deux graines distinctes donnent des suites distinctes")

	# L'etat reste dans le domaine declare — jamais de debordement d'entier.
	var e: int = Rng.graine(-7)
	h.ok(e >= 0 and e < Rng.MODULO, "rng: la graine negative est normalisee dans le domaine")
	for _i in range(50):
		e = Rng.suivant(e)
		if e < 0 or e >= Rng.MODULO:
			break
	h.ok(e >= 0 and e < Rng.MODULO, "rng: l'etat reste dans le domaine sur 50 crans")

	# Tirage borne : la valeur est toujours dans [0, borne[.
	var etat: int = Rng.graine(1)
	var hors_borne: int = 0
	for _i in range(200):
		var t: Dictionary = Rng.tirer(etat, 4)
		etat = t["etat"]
		if t["valeur"] < 0 or t["valeur"] >= 4:
			hors_borne += 1
	h.eq(hors_borne, 0, "rng: 200 tirages restent dans [0, 4[")

	# Variance NON NULLE : un generateur qui rendrait toujours la meme valeur passerait
	# tous les tests de reproductibilite ci-dessus sans rien generer.
	var vues := {}
	etat = Rng.graine(1)
	for _i in range(200):
		var t: Dictionary = Rng.tirer(etat, 4)
		etat = t["etat"]
		vues[t["valeur"]] = true
	h.gt(vues.size(), 1, "rng: au moins deux valeurs distinctes sur 200 tirages")

	# Borne nulle ou negative : aucune consommation, aucun effet de bord.
	var neutre: Dictionary = Rng.tirer(1234, 0)
	h.eq(neutre["valeur"], 0, "rng: borne 0 rend la valeur 0")
	h.eq(neutre["etat"], 1234, "rng: borne 0 ne consomme pas l'etat")

	# L'etat du generateur EST un champ de l'etat de partie, compare comme les autres.
	var s1 = State.initial(Maze, 9)
	var s2 = State.initial(Maze, 9)
	h.eq(s1.rng_etat, s2.rng_etat, "rng: etat de generateur identique au tick 0")
	for _t in range(30):
		s1 = Loop.step(s1, Maze.AUCUNE)["etat"]
		s2 = Loop.step(s2, Maze.AUCUNE)["etat"]
		if s1.rng_etat != s2.rng_etat:
			break
	h.eq(s1.rng_etat, s2.rng_etat, "rng: etat de generateur identique apres 30 ticks")
