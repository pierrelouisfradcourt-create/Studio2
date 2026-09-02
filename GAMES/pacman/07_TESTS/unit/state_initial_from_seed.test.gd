# state_initial_from_seed.test.gd — ligne state.initial_from_seed, capacite F1.
# Comparaison CHAMP PAR CHAMP de l'etat au tick 0 d'une partie relancee avec l'etat au
# tick 0 de la premiere : tous les champs sont egaux, y compris la phase de l'horloge et
# le rang de capture.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func run(h) -> void:
	var a = State.initial(Maze, 1)
	var b = State.initial(Maze, 1)
	h.eq(a.egal_profond(b), true, "state.initial: deux constructions de meme graine sont egales")

	# Valeurs de depart EXACTES, champ par champ.
	h.eq(a.pac, Maze.DEPART_PACMAN, "state.initial: position de depart")
	h.eq(a.pac_dir, Maze.DEPART_DIRECTION, "state.initial: direction de depart")
	h.eq(a.pac_attente, Maze.AUCUNE, "state.initial: aucune demande en attente")
	h.eq(a.score, 0, "state.initial: score a zero")
	h.eq(a.consommees, 0, "state.initial: aucun collectible consomme")
	h.eq(a.total_pose, 244, "state.initial: total pose produit par la pose")
	# TRIAGE V6 : COUNT_FROZEN (5 -> 3). `a` est construit SANS reglages, donc dans le mode
	# par defaut — le mode du defi depuis la decision Pierre du 2026-08-06. La forme de
	# l'assertion (egalite stricte sur litteral) est INCHANGEE ; seule la valeur figee bouge.
	h.eq(a.vies, 3, "state.initial: trois vies dans le mode par defaut")
	h.eq(a.ticks, 0, "state.initial: compteur de ticks a zero")
	h.eq(a.horloge, 0, "state.initial: horloge au premier segment")
	h.eq(a.effraye_restant, 0, "state.initial: aucune fenetre Effraye active")
	h.eq(a.rang_capture, 0, "state.initial: rang de capture a la premiere valeur")
	h.eq(a.statut, State.Statut.EN_COURS, "state.initial: statut EN COURS")
	h.eq(a.dehors, [true, false, false, false], "state.initial: seul le rouge est dehors")
	h.eq(a.fantomes[0], House.place(Maze, 0), "state.initial: place du rouge")
	h.eq(a.est_valide(), true, "state.initial: l'etat construit est structurellement valide")

	# La GRAINE change l'etat du generateur — et rien d'autre au tick 0.
	var c = State.initial(Maze, 2)
	h.ok(a.rng_etat != c.rng_etat, "state.initial: deux graines, deux etats de generateur")
	h.eq(a.pac, c.pac, "state.initial: la graine ne deplace pas Pac-Man")
	h.eq(a.pastilles, c.pastilles, "state.initial: la graine ne change pas la pose")

	# Une partie RELANCEE est egale, champ par champ, a la premiere au tick 0.
	var jouee = State.initial(Maze, 1)
	for _t in range(40):
		jouee = Loop.step(jouee, Maze.GAUCHE)["etat"]
	var relancee = Restart.relancer(Maze, 1)
	h.eq(relancee.egal_profond(State.initial(Maze, 1)), true,
		"state.initial: la relance egale l'etat initial champ par champ")
	h.eq(Restart.aucune_fuite(relancee, Maze, 1), true, "state.initial: aucun champ ne fuit de la partie precedente")
	h.ok(not jouee.egal_profond(relancee), "state.initial: la partie jouee a bien diverge de l'initial")

	# Le clone est INDEPENDANT : muter la copie ne touche pas l'original.
	var copie = a.clone()
	copie.score = 999
	copie.pastilles[0] = 1
	copie.fantomes[0] = Vector2i(0, 0)
	h.eq(a.score, 0, "state.initial: le clone n'affecte pas le score d'origine")
	h.eq(a.fantomes[0], House.place(Maze, 0), "state.initial: le clone n'affecte pas les positions d'origine")
	h.ok(not a.egal_profond(copie), "state.initial: le clone modifie n'est plus egal")
