# core_input_action.gd — ligne CORE core.input.
# Une action emise sur le canal d'entree PUBLIC — le MEME pour le clavier et pour le bot —
# modifie l'etat de jeu de facon OBSERVABLE : pour chaque action du vocabulaire ferme
# (quatre directions, relance), le nombre de commandes SANS EFFET OBSERVABLE est
# EXACTEMENT 0. Une commande exposee mais inerte est un FAIL.
extends RefCounted

const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")


func _fixture(position: Vector2i, direction: Vector2i) -> Object:
	var s = State.initial(Maze, 1)
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	s.pac = position
	s.pac_dir = direction
	s.pac_attente = Maze.AUCUNE
	return s


func run(h) -> void:
	# LES QUATRE DIRECTIONS, depuis un vrai carrefour : chacune a un effet OBSERVABLE.
	var carrefour := Vector2i(6, 23)
	var sans_effet: int = 0
	var testees: int = 0
	for touche in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		var direction: Vector2i = InputAdapter.direction_de_touche(touche)
		h.ok(Maze.DIRECTIONS.has(direction), "core.input: la touche %d porte une direction" % touche)
		var s = _fixture(carrefour, direction)
		var avant: Dictionary = Observable.projeter(s)
		var apres: Dictionary = Observable.projeter(Loop.step(s, direction)["etat"])
		testees += 1
		if apres["pac"] == avant["pac"]:
			sans_effet += 1
	h.eq(testees, 4, "core.input: les quatre directions du vocabulaire ferme sont exercees")
	h.eq(sans_effet, 0, "core.input: 0 direction sans effet observable")

	# LA RELANCE : cinquieme action du vocabulaire ferme, effet OBSERVABLE.
	var fini = State.initial(Maze, 1)
	for _t in range(50):
		fini = Loop.step(fini, Maze.GAUCHE)["etat"]
	fini.vies = 0
	Status.appliquer(fini)
	var avant_fin: Dictionary = Observable.projeter(fini)
	h.eq(avant_fin["statut_nom"], "PERDU", "core.input: la partie est bien terminee avant la relance")
	h.eq(InputAdapter.est_relance(KEY_R), true, "core.input: la touche de relance est reconnue")
	var apres_relance: Dictionary = Observable.projeter(Restart.relancer(Maze, Boot.GRAINE_INITIALE))
	h.ok(apres_relance["statut_nom"] != avant_fin["statut_nom"], "core.input: la relance a un effet observable")
	h.eq(apres_relance["statut_nom"], "EN COURS", "core.input: la relance rend la partie jouable")

	# LE MEME CANAL pour le clavier et pour le bot : la normalisation est unique.
	var s_clavier = _fixture(carrefour, Maze.HAUT)
	var s_bot = _fixture(carrefour, Maze.HAUT)
	var par_clavier = Loop.step(s_clavier, InputAdapter.direction_de_touche(KEY_LEFT))["etat"]
	var par_bot = Loop.step(s_bot, InputAdapter.normaliser_direction(Maze.GAUCHE))["etat"]
	h.eq(par_clavier.pac, par_bot.pac, "core.input: clavier et bot produisent le meme effet")
	h.eq(par_clavier.pac_dir, par_bot.pac_dir, "core.input: meme direction effectuee")

	# FALSIFICATION — canal NEUTRALISE : le nombre d'actions ayant un effet est
	# EXACTEMENT 0. Sans cette contre-epreuve, un canal inerte passerait pour vert.
	var avec_effet: int = 0
	for touche in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		var s = _fixture(carrefour, InputAdapter.direction_de_touche(touche))
		var avant: Vector2i = s.pac
		# Canal neutralise : l'action emise est remplacee par « aucune entree », et la
		# direction courante est elle aussi neutralisee (Pac-Man n'a plus d'elan).
		s.pac_dir = Maze.AUCUNE
		var apres = Loop.step(s, Maze.AUCUNE)["etat"]
		if apres.pac != avant:
			avec_effet += 1
	h.eq(avec_effet, 0, "core.input: canal neutralise -> 0 action avec effet")

	# Une touche NON LIEE est inerte par construction, et c'est le comportement voulu :
	# elle n'appartient pas au vocabulaire ferme.
	h.eq(InputAdapter.traduire(KEY_F7)["genre"], "aucune", "core.input: une touche non liee est hors vocabulaire")
	h.eq(InputAdapter.direction_de_touche(KEY_F7), Maze.AUCUNE, "core.input: elle ne porte aucune direction")
