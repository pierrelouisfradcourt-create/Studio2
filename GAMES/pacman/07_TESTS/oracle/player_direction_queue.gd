# player_direction_queue.gd — ligne player.direction_queue, capacite F11.
# Une SEULE pression a un tick ou le virage est impossible ; sans aucune autre entree,
# la demande reste EN ATTENTE jusqu'au premier tick ou ce virage devient praticable.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func _sans_fantomes(graine: int) -> Object:
	var s = State.initial(Maze, graine)
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	return s


func run(h) -> void:
	# Fixture : Pac-Man dans le couloir du bas (ligne 32), qui court vers la droite.
	# Le virage vers le haut n'est possible qu'a certaines colonnes.
	var s = _sans_fantomes(1)
	s.pac = Vector2i(2, 32)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	h.eq(Maze.praticable(Vector2i(2, 31)), false, "player.queue: fixture — pas de virage en (2,32)")
	h.eq(Maze.praticable(Vector2i(12, 31)), true, "player.queue: fixture — virage possible en (12,32)")

	# UNE SEULE pression vers le haut, puis plus AUCUNE entree.
	s = Loop.step(s, Maze.HAUT)["etat"]
	h.eq(s.pac_attente, Maze.HAUT, "player.queue: la demande impossible entre en attente")
	h.eq(s.pac_dir, Maze.DROITE, "player.queue: la direction effectuee reste celle du tick precedent")
	h.eq(s.pac, Vector2i(3, 32), "player.queue: Pac-Man a avance d'une case vers la droite")

	# Ticks suivants SANS entree : la demande est CONSERVEE tant qu'elle est impraticable.
	var ticks_en_attente: int = 0
	var vire_a: int = -1
	for _t in range(20):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		if s.pac_attente == Maze.HAUT:
			ticks_en_attente += 1
		elif vire_a < 0:
			vire_a = s.pac.x
			break
	h.gt(ticks_en_attente, 0, "player.queue: la demande survit plusieurs ticks sans entree")
	h.eq(vire_a, 12, "player.queue: le virage a lieu au PREMIER tick praticable, en colonne 12")
	h.eq(s.pac_dir, Maze.HAUT, "player.queue: la direction effectuee devient celle demandee")
	h.eq(s.pac, Vector2i(12, 31), "player.queue: Pac-Man a bien tourne vers le haut")
	h.eq(s.pac_attente, Maze.AUCUNE, "player.queue: la file est videe apres consommation")

	# PROFONDEUR 1 : une seconde demande ECRASE la premiere (la derniere gagne).
	var t = _sans_fantomes(1)
	t.pac = Vector2i(2, 32)
	t.pac_dir = Maze.DROITE
	t.pac_attente = Maze.AUCUNE
	t = Loop.step(t, Maze.HAUT)["etat"]
	h.eq(t.pac_attente, Maze.HAUT, "player.queue: premiere demande en file")
	t = Loop.step(t, Maze.BAS)["etat"]
	h.eq(t.pac_attente, Maze.BAS, "player.queue: la seconde demande ecrase la premiere")

	# Une demande PRATICABLE est consommee tout de suite, jamais mise en attente.
	var u = _sans_fantomes(1)
	u.pac = Vector2i(12, 32)
	u.pac_dir = Maze.DROITE
	u.pac_attente = Maze.AUCUNE
	u = Loop.step(u, Maze.HAUT)["etat"]
	h.eq(u.pac_attente, Maze.AUCUNE, "player.queue: une demande praticable n'attend pas")
	h.eq(u.pac, Vector2i(12, 31), "player.queue: elle est appliquee des le tick suivant")
