# maze_tunnel_wrap.gd — ligne maze.tunnel_wrap, capacite F8.
# Etat sur DEUX ticks consecutifs : la colonne passe de l'extremite droite a l'extremite
# gauche (ou l'inverse), la ligne est INCHANGEE, le compteur de vies est INCHANGE, le
# statut reste EN COURS.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")


func run(h) -> void:
	# Fonction pure de bouclage, valeurs exactes.
	h.eq(Maze.boucler(Vector2i(-1, 17)), Vector2i(27, 17), "maze.wrap: -1 devient 27")
	h.eq(Maze.boucler(Vector2i(28, 17)), Vector2i(0, 17), "maze.wrap: 28 devient 0")
	h.eq(Maze.boucler(Vector2i(13, 17)), Vector2i(13, 17), "maze.wrap: l'interieur ne bouge pas")
	h.eq(Maze.boucler(Vector2i(-1, 5)).y, 5, "maze.wrap: la ligne n'est jamais modifiee")

	# Le bouclage est le MEME pour toutes les entites : la fonction n'a pas d'argument
	# d'entite, donc aucune divergence n'est exprimable.
	h.eq(Maze.case_suivante(Vector2i(0, 17), Maze.GAUCHE), Vector2i(27, 17),
		"maze.wrap: pas a gauche depuis le bord gauche")
	h.eq(Maze.case_suivante(Vector2i(27, 17), Maze.DROITE), Vector2i(0, 17),
		"maze.wrap: pas a droite depuis le bord droit")

	# SUR DEUX TICKS CONSECUTIFS d'une partie reelle, pilote par le canal public.
	var s = State.initial(Maze, 1)
	s.pac = Vector2i(0, Maze.LIGNE_TUNNEL)
	s.pac_dir = Maze.GAUCHE
	s.pac_attente = Maze.AUCUNE
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 9999
	var avant: Dictionary = Observable.projeter(s)
	var apres = Loop.step(s, Maze.GAUCHE)["etat"]
	var releve: Dictionary = Observable.projeter(apres)

	h.eq(avant["pac"][0], 0, "maze.wrap: colonne 0 au tick precedent")
	h.eq(releve["pac"][0], Maze.LARGEUR - 1, "maze.wrap: colonne 27 au tick suivant")
	h.eq(releve["pac"][1], avant["pac"][1], "maze.wrap: la ligne est inchangee")
	h.eq(releve["vies"], avant["vies"], "maze.wrap: le compteur de vies est inchange")
	h.eq(releve["statut_nom"], "EN COURS", "maze.wrap: le statut reste EN COURS")

	# Et dans l'autre sens, sur deux ticks consecutifs.
	var t = State.initial(Maze, 1)
	t.pac = Vector2i(Maze.LARGEUR - 1, Maze.LIGNE_TUNNEL)
	t.pac_dir = Maze.DROITE
	t.pac_attente = Maze.AUCUNE
	for i in range(4):
		t.dehors[i] = false
		t.sorties_maison[i] = 9999
	var t2 = Loop.step(t, Maze.DROITE)["etat"]
	var r2: Dictionary = Observable.projeter(t2)
	h.eq(r2["pac"][0], 0, "maze.wrap: de 27 a 0 dans l'autre sens")
	h.eq(r2["pac"][1], Maze.LIGNE_TUNNEL, "maze.wrap: la ligne reste celle du tunnel")
	h.eq(r2["statut_nom"], "EN COURS", "maze.wrap: statut EN COURS apres bouclage inverse")

	# Le bouclage n'existe QUE sur la ligne du tunnel : ailleurs le bord est un mur.
	var u = State.initial(Maze, 1)
	u.pac = Vector2i(1, 4)
	u.pac_dir = Maze.GAUCHE
	u.pac_attente = Maze.AUCUNE
	for i in range(4):
		u.dehors[i] = false
		u.sorties_maison[i] = 9999
	var u2 = Loop.step(u, Maze.GAUCHE)["etat"]
	h.eq(u2.pac, Vector2i(1, 4), "maze.wrap: hors ligne de tunnel, le bord bute contre le mur")
