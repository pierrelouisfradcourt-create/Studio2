# runtime_tick_cadence.gd — ligne runtime.tick_cadence, capacite F44.
# Deux releves d'etat separes par une fenetre DECLAREE de ticks, sans injecter aucune
# entree : la boucle a produit des ticks et les positions ont change.
# Le cadenceur est le SEUL endroit du jeu ou une horloge de plateforme est lue.
extends RefCounted

const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const FENETRE: int = 30


func run(h) -> void:
	var periode: float = P.PERIODE_TICK_MS

	# En deca de la periode : aucun tick, le temps s'accumule.
	var r1: Dictionary = RuntimeLoop.avancer(0.0, periode / 2.0, periode, false)
	h.eq(r1["ticks"], 0, "runtime.cadence: aucun tick avant la periode")
	h.eq(r1["accumulateur"], periode / 2.0, "runtime.cadence: le temps s'accumule")

	# A la periode : exactement un tick.
	var r2: Dictionary = RuntimeLoop.avancer(0.0, periode, periode, false)
	h.eq(r2["ticks"], 1, "runtime.cadence: un tick exactement a la periode")
	h.eq(r2["accumulateur"], 0.0, "runtime.cadence: l'accumulateur est decremente d'une periode")

	# AUCUN RATTRAPAGE : une trame tres longue ne produit qu'UN tick, jamais une rafale.
	var r3: Dictionary = RuntimeLoop.avancer(0.0, periode * 10.0, periode, false)
	h.eq(r3["ticks"], 1, "runtime.cadence: un seul tick meme apres une trame tres longue")
	h.eq(r3["accumulateur"], periode * 9.0, "runtime.cadence: le reste demeure dans l'accumulateur")

	# GELE (partie terminee) : aucun tick, aucun temps accumule.
	var r4: Dictionary = RuntimeLoop.avancer(50.0, periode * 5.0, periode, true)
	h.eq(r4["ticks"], 0, "runtime.cadence: aucun tick quand la boucle est gelee")
	h.eq(r4["accumulateur"], 0.0, "runtime.cadence: aucun temps n'est accumule au gel")

	# Le cadenceur est PUR : meme entree, meme sortie.
	var a: Dictionary = RuntimeLoop.avancer(10.0, 20.0, periode, false)
	var b: Dictionary = RuntimeLoop.avancer(10.0, 20.0, periode, false)
	h.eq(a["accumulateur"], b["accumulateur"], "runtime.cadence: cadenceur pur et deterministe")

	# SUR UNE FENETRE DECLAREE, SANS ENTREE : la boucle a produit des ticks et les
	# positions ont change.
	var jeu = State.initial(Maze, 1)
	var avant: Dictionary = Observable.projeter(jeu)
	var ticks_produits: int = 0
	var accumulateur: float = 0.0
	for _trame in range(FENETRE):
		var pas: Dictionary = RuntimeLoop.avancer(accumulateur, periode, periode, false)
		accumulateur = pas["accumulateur"]
		if pas["ticks"] == 1:
			jeu = Loop.step(jeu, Maze.AUCUNE)["etat"]
			ticks_produits += 1
	var apres: Dictionary = Observable.projeter(jeu)
	h.eq(ticks_produits, FENETRE, "runtime.cadence: la boucle a produit un tick par trame de periode")
	h.eq(apres["tick"] - avant["tick"], FENETRE, "runtime.cadence: l'etat a bien avance d'autant")
	h.ok(apres["pac"] != avant["pac"], "runtime.cadence: la position de Pac-Man a change")
	var bouges: int = 0
	for i in range(4):
		if apres["fantomes"][i] != avant["fantomes"][i]:
			bouges += 1
	h.gt(bouges, 0, "runtime.cadence: au moins un fantome a change de position")
