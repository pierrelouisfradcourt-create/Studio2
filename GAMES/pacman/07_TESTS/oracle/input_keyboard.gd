# input_keyboard.gd — ligne input.keyboard, capacite F43.
# Etat au tick qui SUIT l'appui : la direction effectuee est EXACTEMENT la direction
# demandee, et la position a avance d'UNE case dans cette direction.
extends RefCounted

const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func run(h) -> void:
	# Traduction des touches vers le vocabulaire FERME de directions.
	h.eq(InputAdapter.direction_de_touche(KEY_UP), Maze.HAUT, "input.keyboard: fleche haut")
	h.eq(InputAdapter.direction_de_touche(KEY_DOWN), Maze.BAS, "input.keyboard: fleche bas")
	h.eq(InputAdapter.direction_de_touche(KEY_LEFT), Maze.GAUCHE, "input.keyboard: fleche gauche")
	h.eq(InputAdapter.direction_de_touche(KEY_RIGHT), Maze.DROITE, "input.keyboard: fleche droite")

	# Une touche NON LIEE rend « aucune entree » : jamais une exception, jamais un effet.
	h.eq(InputAdapter.direction_de_touche(KEY_F7), Maze.AUCUNE, "input.keyboard: touche non liee")
	h.eq(InputAdapter.traduire(KEY_F7)["genre"], "aucune", "input.keyboard: genre `aucune`")

	# La normalisation refuse tout ce qui n'est pas du vocabulaire ferme : c'est ce qui
	# rend le canal UNIQUE — le bot ne peut pas emettre autre chose que le clavier.
	h.eq(InputAdapter.normaliser_direction(Vector2i(3, 3)), Maze.AUCUNE,
		"input.keyboard: une valeur hors vocabulaire est refusee")
	h.eq(InputAdapter.normaliser_direction(Maze.HAUT), Maze.HAUT,
		"input.keyboard: une direction du vocabulaire passe telle quelle")

	# ETAT AU TICK QUI SUIT L'APPUI, pour CHAQUE direction praticable depuis un carrefour.
	var carrefour := Vector2i(6, 23)
	var testees: int = 0
	var ecarts: int = 0
	for touche in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var direction: Vector2i = InputAdapter.direction_de_touche(touche)
		var cible: Vector2i = Maze.case_suivante(carrefour, direction)
		if not Maze.praticable(cible):
			continue
		var s = State.initial(Maze, 1)
		for i in range(4):
			s.dehors[i] = false
			s.sorties_maison[i] = 99999
		s.pac = carrefour
		s.pac_dir = direction
		s.pac_attente = Maze.AUCUNE
		var apres = Loop.step(s, direction)["etat"]
		testees += 1
		if apres.pac_dir != direction:
			ecarts += 1
		if apres.pac != cible:
			ecarts += 1
	h.eq(testees, 4, "input.keyboard: les quatre directions sont praticables au carrefour")
	h.eq(ecarts, 0, "input.keyboard: direction effectuee et position exactes au tick suivant")

	# UN SEUL CANAL : la direction emise par le bot passe par la meme normalisation.
	var s2 = State.initial(Maze, 1)
	for i in range(4):
		s2.dehors[i] = false
		s2.sorties_maison[i] = 99999
	s2.pac = carrefour
	s2.pac_dir = Maze.HAUT
	var par_clavier = Loop.step(s2, InputAdapter.direction_de_touche(KEY_LEFT))["etat"]
	var par_bot = Loop.step(s2, InputAdapter.normaliser_direction(Maze.GAUCHE))["etat"]
	h.eq(par_clavier.pac, par_bot.pac, "input.keyboard: clavier et bot passent par le meme canal")
	h.eq(par_clavier.pac_dir, par_bot.pac_dir, "input.keyboard: meme direction effectuee")

	# Un evenement de moteur qui n'est pas un appui rend -1.
	var relache := InputEventKey.new()
	relache.pressed = false
	relache.keycode = KEY_UP
	h.eq(InputAdapter.keycode_de_event(relache), -1, "input.keyboard: un relachement n'est pas un appui")
	var appui := InputEventKey.new()
	appui.pressed = true
	appui.echo = false
	appui.keycode = KEY_UP
	h.eq(InputAdapter.keycode_de_event(appui), KEY_UP, "input.keyboard: un appui est reconnu")
