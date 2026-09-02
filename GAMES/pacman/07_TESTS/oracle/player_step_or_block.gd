# player_step_or_block.gd — ligne player.step_or_block, capacite F13.
# Etat avant et apres le tick de butee : la position reste sur la DERNIERE case de
# couloir, ne franchit pas la case de mur, ne saute vers AUCUNE case non adjacente ; aux
# ticks suivants sans entree, la position ne change plus.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func run(h) -> void:
	# Fonction pure : un pas, ou rien.
	h.eq(Player.avancer(Maze, Vector2i(12, 32), Maze.DROITE), Vector2i(13, 32), "player.step: un pas a droite")
	h.eq(Player.avancer(Maze, Vector2i(26, 32), Maze.DROITE), Vector2i(26, 32), "player.step: butee contre le mur")
	h.eq(Player.avancer(Maze, Vector2i(12, 32), Maze.AUCUNE), Vector2i(12, 32), "player.step: aucune direction, aucun pas")

	# Fixture de butee : Pac-Man court vers la droite au bout du couloir du bas.
	var s = State.initial(Maze, 1)
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	s.pac = Vector2i(25, 32)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	h.eq(Maze.praticable(Vector2i(26, 32)), true, "player.step: fixture — (26,32) est un couloir")
	h.eq(Maze.praticable(Vector2i(27, 32)), false, "player.step: fixture — (27,32) est un mur")

	var t1 = Loop.step(s, Maze.AUCUNE)["etat"]
	h.eq(t1.pac, Vector2i(26, 32), "player.step: Pac-Man atteint la derniere case de couloir")

	var avant: Vector2i = t1.pac
	var t2 = Loop.step(t1, Maze.AUCUNE)["etat"]
	h.eq(t2.pac, Vector2i(26, 32), "player.step: la position reste sur la derniere case de couloir")
	h.ok(t2.pac != Vector2i(27, 32), "player.step: la case de mur n'est jamais franchie")
	h.ok(Maze.distance(t2.pac, avant) <= 1, "player.step: aucun saut vers une case non adjacente")

	# Ticks suivants SANS entree : la position ne change PLUS.
	var immobile: bool = true
	var courant = t2
	for _t in range(10):
		courant = Loop.step(courant, Maze.AUCUNE)["etat"]
		if courant.pac != Vector2i(26, 32):
			immobile = false
	h.eq(immobile, true, "player.step: la position ne change plus sur 10 ticks sans entree")
	h.eq(courant.pac_dir, Maze.DROITE, "player.step: la direction effectuee est conservee a la butee")

	# AUCUN SAUT sur une partie entiere : chaque tick deplace d'au plus une case
	# adjacente (le bouclage de tunnel compte pour une case, par construction de maze).
	var u = State.initial(Maze, 1)
	for i in range(4):
		u.dehors[i] = false
		u.sorties_maison[i] = 99999
	var sauts: int = 0
	var rafale: Array = [Maze.GAUCHE, Maze.HAUT, Maze.DROITE, Maze.BAS]
	for r in range(60):
		var precedent: Vector2i = u.pac
		u = Loop.step(u, rafale[r % 4])["etat"]
		var voisines: Array = Maze.voisins_praticables(precedent)
		if u.pac != precedent and not voisines.has(u.pac):
			sauts += 1
	h.eq(sauts, 0, "player.step: 0 saut vers une case non adjacente sur 60 ticks")

	# Jamais dans un mur, a aucun tick.
	h.eq(Maze.praticable(u.pac), true, "player.step: Pac-Man n'est jamais dans un mur")
