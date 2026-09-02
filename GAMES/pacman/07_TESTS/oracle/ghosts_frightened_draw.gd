# ghosts_frightened_draw.gd — ligne ghosts.frightened_draw, capacite F21.
# Sur une fenetre DECLAREE en etat Effraye, la direction est TIREE parmi les sorties
# praticables au moyen du generateur seede : la distance Pac-Man / fantome ne decroit pas
# strictement a chaque deplacement.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Rng = preload("res://05_SYSTEMS/rng/rng.gd")

const FENETRE: int = 40


func run(h) -> void:
	# Le tirage CONSOMME l'etat du generateur : c'est ce qui le rend rejouable.
	var t1: Dictionary = Ghosts.tirer_direction(Maze, Vector2i(6, 23), Maze.DROITE, Rng.graine(1))
	h.ok(t1["etat_rng"] != Rng.graine(1), "ghosts.frightened: le tirage consomme le generateur")
	h.ok(Maze.DIRECTIONS.has(t1["direction"]), "ghosts.frightened: la direction tiree est du vocabulaire ferme")

	# La direction tiree est TOUJOURS une sortie praticable et jamais un demi-tour.
	var hors_sorties: int = 0
	var etat: int = Rng.graine(5)
	for _i in range(60):
		var tirage: Dictionary = Ghosts.tirer_direction(Maze, Vector2i(6, 23), Maze.DROITE, etat)
		etat = tirage["etat_rng"]
		if not Ghosts.sorties_candidates(Maze, Vector2i(6, 23), Maze.DROITE).has(tirage["direction"]):
			hors_sorties += 1
	h.eq(hors_sorties, 0, "ghosts.frightened: 60 tirages restent dans les sorties candidates")

	# Meme etat de generateur -> meme direction : le tirage est REJOUABLE.
	var a: Dictionary = Ghosts.tirer_direction(Maze, Vector2i(6, 23), Maze.DROITE, 123456)
	var b: Dictionary = Ghosts.tirer_direction(Maze, Vector2i(6, 23), Maze.DROITE, 123456)
	h.eq(a["direction"], b["direction"], "ghosts.frightened: meme etat de generateur, meme direction")
	h.eq(a["etat_rng"], b["etat_rng"], "ghosts.frightened: meme etat de generateur, meme suite")

	# VARIANCE du tirage : plusieurs directions apparaissent. Un tirage constant
	# satisferait la rejouabilite sans rien tirer du tout.
	var vues := {}
	etat = Rng.graine(9)
	for _i in range(60):
		var tirage: Dictionary = Ghosts.tirer_direction(Maze, Vector2i(6, 23), Maze.DROITE, etat)
		etat = tirage["etat_rng"]
		vues[tirage["direction"]] = true
	h.gt(vues.size(), 1, "ghosts.frightened: au moins deux directions distinctes sur 60 tirages")

	# SUR UNE PARTIE : en etat Effraye, la distance ne decroit PAS strictement a chaque
	# deplacement — le fantome ne poursuit plus.
	var s = State.initial(Maze, 21)
	s.pac = Vector2i(2, 32)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	s.fantomes[Targeting.ROUGE] = Vector2i(6, 23)
	s.dirs_fantomes[Targeting.ROUGE] = Maze.DROITE
	s.dehors[Targeting.ROUGE] = true
	for i in range(1, 4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	Chase.armer_effraye(s)
	s.effraye_restant = FENETRE * 2

	var precedente: Vector2i = s.fantomes[Targeting.ROUGE]
	var distance_precedente: int = Targeting.distance(s.pac, precedente)
	var deplacements: int = 0
	var non_decroissances: int = 0
	var toujours_effraye: bool = true
	for _t in range(FENETRE):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		if s.etats_fantomes[Targeting.ROUGE] != Chase.Mode.EFFRAYE:
			toujours_effraye = false
		var courante: Vector2i = s.fantomes[Targeting.ROUGE]
		if courante != precedente:
			deplacements += 1
			var d: int = Targeting.distance(s.pac, courante)
			if not (d < distance_precedente):
				non_decroissances += 1
			distance_precedente = d
			precedente = courante
	h.eq(toujours_effraye, true, "ghosts.frightened: le fantome reste Effraye sur la fenetre")
	h.gt(deplacements, 0, "ghosts.frightened: le fantome s'est reellement deplace")
	h.gt(non_decroissances, 0,
		"ghosts.frightened: la distance ne decroit PAS strictement a chaque deplacement")
