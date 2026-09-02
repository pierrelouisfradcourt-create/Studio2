# player_resolved_direction.gd — ligne player.resolved_direction, capacite F12.
# Etat au tick qui SUIT l'appui impossible : la direction effectuee est EGALE a la
# direction effectuee au tick precedent, et la position a avance d'UNE case dans cette
# direction.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func run(h) -> void:
	# Fonction pure de resolution : demande praticable -> elle est retenue.
	var r1: Dictionary = Player.direction_resolue(Maze, Vector2i(12, 32), Maze.DROITE, Maze.HAUT)
	h.eq(r1["direction"], Maze.HAUT, "player.resolved: la demande praticable est retenue")
	h.eq(r1["attente"], Maze.AUCUNE, "player.resolved: la file est videe")

	# Demande IMPRATICABLE -> direction courante conservee, demande maintenue en attente.
	var r2: Dictionary = Player.direction_resolue(Maze, Vector2i(2, 32), Maze.DROITE, Maze.HAUT)
	h.eq(r2["direction"], Maze.DROITE, "player.resolved: la direction courante est conservee")
	h.eq(r2["attente"], Maze.HAUT, "player.resolved: la demande impraticable reste en attente")

	# Aucune demande -> direction courante, sans effet de bord.
	var r3: Dictionary = Player.direction_resolue(Maze, Vector2i(12, 32), Maze.DROITE, Maze.AUCUNE)
	h.eq(r3["direction"], Maze.DROITE, "player.resolved: sans demande, la direction courante tient")
	h.eq(r3["attente"], Maze.AUCUNE, "player.resolved: sans demande, la file reste vide")

	# SUR UNE PARTIE : etat au tick qui suit l'appui impossible.
	var s = State.initial(Maze, 1)
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	s.pac = Vector2i(2, 32)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	var dir_avant: Vector2i = s.pac_dir
	var pos_avant: Vector2i = s.pac

	var apres = Loop.step(s, Maze.HAUT)["etat"]
	h.eq(apres.pac_dir, dir_avant, "player.resolved: direction EGALE a celle du tick precedent")
	h.eq(apres.pac, Maze.case_suivante(pos_avant, dir_avant),
		"player.resolved: la position a avance d'une case dans CETTE direction")
	h.eq(Maze.distance(apres.pac, pos_avant), 1, "player.resolved: exactement une case parcourue")

	# L'appui impossible n'a AUCUN autre effet de bord : score, vies, consommes.
	h.eq(apres.vies, s.vies, "player.resolved: aucune vie perdue")
	h.eq(apres.statut, State.Statut.EN_COURS, "player.resolved: la partie continue")

	# Le tick d'apres, toujours sans entree : la direction tient encore.
	var apres2 = Loop.step(apres, Maze.AUCUNE)["etat"]
	h.eq(apres2.pac_dir, dir_avant, "player.resolved: la direction tient au tick suivant")
	h.eq(apres2.pac, Maze.case_suivante(apres.pac, dir_avant),
		"player.resolved: encore une case dans la meme direction")

	# Une DIAGONALE n'est pas une direction : elle n'est jamais effectuee.
	var t = State.initial(Maze, 1)
	for i in range(4):
		t.dehors[i] = false
		t.sorties_maison[i] = 99999
	var t2 = Loop.step(t, Vector2i(1, 1))["etat"]
	h.eq(t2.pac_dir, Maze.DEPART_DIRECTION, "player.resolved: une diagonale n'est jamais effectuee")
	h.eq(t2.pac_attente, Maze.AUCUNE, "player.resolved: une diagonale n'entre pas en file")
