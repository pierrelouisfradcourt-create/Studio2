# score_pellet_value.test.gd — ligne score.pellet_value, capacite F31.
# Au tick de consommation d'une super-pastille : le score a augmente d'EXACTEMENT 50 et
# les restantes ont baisse d'EXACTEMENT 1.
extends RefCounted

const Score = preload("res://05_SYSTEMS/score/score.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")


func run(h) -> void:
	h.eq(Score.valeur_collectible(false), 10, "score.pellet: 10 points par pastille ordinaire")
	h.eq(Score.valeur_collectible(true), 50, "score.pellet: 50 points par super-pastille")
	h.ok(Score.valeur_collectible(true) != Score.valeur_collectible(false),
		"score.pellet: les deux natures ne valent pas la meme chose")

	# Sur une partie : consommer une super-pastille fait +50 et -1 restante, exactement.
	var s = State.initial(Maze, 1)
	var supers: Array = Pellets.positions_super(Maze, s.pastilles)
	h.eq(supers.size(), 4, "score.pellet: quatre super-pastilles sur la carte")

	# Fixture de mesure : Pac-Man pose sur une super-pastille, un tick sans deplacement.
	var cible: Vector2i = supers[0]
	s.pac = Maze.case_suivante(cible, Maze.DROITE)
	s.pac_dir = Maze.GAUCHE
	s.pac_attente = Maze.AUCUNE
	var score_avant: int = s.score
	var restantes_avant: int = Observable.projeter(s)["restantes"]
	var apres = Loop.step(s, Maze.GAUCHE)["etat"]
	h.eq(apres.pac, cible, "score.pellet: Pac-Man est bien arrive sur la super-pastille")
	h.eq(apres.score - score_avant, 50, "score.pellet: le score a monte d'exactement 50")
	h.eq(restantes_avant - Observable.projeter(apres)["restantes"], 1,
		"score.pellet: les restantes ont baisse d'exactement 1")

	# Meme mesure pour une pastille ordinaire : +10 et -1.
	var t = State.initial(Maze, 1)
	var ordinaire := Vector2i(-1, -1)
	for i in range(t.pastilles.size()):
		if t.pastilles[i] == Pellets.Contenu.PASTILLE:
			ordinaire = Maze.case_de(i)
			break
	t.pac = Maze.case_suivante(ordinaire, Maze.DROITE)
	t.pac_dir = Maze.GAUCHE
	t.pac_attente = Maze.AUCUNE
	var score_avant2: int = t.score
	var restantes_avant2: int = Observable.projeter(t)["restantes"]
	var apres2 = Loop.step(t, Maze.GAUCHE)["etat"]
	h.eq(apres2.pac, ordinaire, "score.pellet: Pac-Man est arrive sur la pastille ordinaire")
	h.eq(apres2.score - score_avant2, 10, "score.pellet: le score a monte d'exactement 10")
	h.eq(restantes_avant2 - Observable.projeter(apres2)["restantes"], 1,
		"score.pellet: une restante de moins pour une pastille ordinaire")
