# end_life_loss.test.gd — ligne end.life_loss, capacite F36.
# Invariant soumis au gate de mutation : un mutant qui retire ZERO vie, DEUX vies, ou
# qui ne repositionne pas les entites au contact, doit etre tue ICI.
extends RefCounted

const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")


func run(h) -> void:
	var s = State.initial(Maze, 1)
	# On eloigne les entites et on consomme des collectibles pour mesurer le retour.
	s.pac = Vector2i(1, 4)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.HAUT
	s.horloge = 200
	s.ticks = 250
	s.effraye_restant = 20
	s.rang_capture = 2
	for i in range(4):
		s.dehors[i] = true
		s.fantomes[i] = Vector2i(1, 4 + i)
	var consommees_avant: int = 17
	s.consommees = consommees_avant
	var pastilles_avant: PackedByteArray = s.pastilles.duplicate()
	var vies_avant: int = s.vies
	var score_avant: int = s.score

	End.perdre_une_vie(s)

	# EXACTEMENT une vie : ni zero, ni deux.
	h.eq(s.vies, vies_avant - 1, "end.life_loss: exactement une vie retiree")
	h.eq(vies_avant - s.vies, 1, "end.life_loss: le decrement vaut 1")

	# Entites replacees aux positions de DEPART.
	h.eq(s.pac, Maze.DEPART_PACMAN, "end.life_loss: Pac-Man revient a sa case de depart")
	h.eq(s.pac_dir, Maze.DEPART_DIRECTION, "end.life_loss: direction de depart restauree")
	h.eq(s.pac_attente, Maze.AUCUNE, "end.life_loss: aucune demande en attente ne survit")
	h.eq(s.fantomes[0], House.place(Maze, 0), "end.life_loss: le rouge revient a sa place")
	h.eq(s.fantomes[1], House.place(Maze, 1), "end.life_loss: le rose revient a sa place")
	h.eq(s.fantomes[2], House.place(Maze, 2), "end.life_loss: le cyan revient a sa place")
	h.eq(s.fantomes[3], House.place(Maze, 3), "end.life_loss: l'orange revient a sa place")
	h.eq(s.dehors, [true, false, false, false], "end.life_loss: seul le rouge est dehors")

	# Horloge revenue a son PREMIER segment.
	h.eq(s.horloge, 0, "end.life_loss: l'horloge revient au premier segment")
	h.eq(s.effraye_restant, 0, "end.life_loss: la fenetre Effraye est fermee")
	h.eq(s.rang_capture, 0, "end.life_loss: le rang de capture repart a zero")

	# Les collectibles CONSOMMES NE REVIENNENT PAS.
	h.eq(s.consommees, consommees_avant, "end.life_loss: le compte de consommes est conserve")
	h.eq(s.pastilles, pastilles_avant, "end.life_loss: la grille de collectibles est intacte")
	h.eq(s.score, score_avant, "end.life_loss: le score n'est pas remis a zero")

	# Les delais de sortie repartent du tick courant, strictement croissants.
	h.eq(s.sorties_maison[0], s.ticks + House.DELAIS_SORTIE[0], "end.life_loss: delai du rouge")
	h.eq(s.sorties_maison[3], s.ticks + House.DELAIS_SORTIE[3], "end.life_loss: delai de l'orange")
	var non_croissants: int = 0
	for i in range(1, s.sorties_maison.size()):
		if not (s.sorties_maison[i] > s.sorties_maison[i - 1]):
			non_croissants += 1
	h.eq(non_croissants, 0, "end.life_loss: delais de sortie strictement croissants")

	# LA DESCENTE COMPLETE, UN CRAN A LA FOIS, JUSQU'A ZERO.
	# TRIAGE V6 : COUNT_FROZEN sur la valeur de depart, INVARIANT sur le reste. Le nombre
	# de vies depend desormais du MODE (decision Pierre du 2026-08-06) : la descente est
	# donc jouee dans le mode qui en donne le PLUS, pour que le bloc garde autant de crans
	# qu'avant — cinq egalites strictes, aucune boucle, aucune assertion perdue. Le mode du
	# defi est verifie juste apres, sur sa propre longueur.
	var t = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.TEST})
	h.eq(t.vies, 5, "end.life_loss: cinq vies au depart dans le mode de la marge")
	End.perdre_une_vie(t)
	h.eq(t.vies, 4, "end.life_loss: quatre vies apres la premiere perte")
	End.perdre_une_vie(t)
	h.eq(t.vies, 3, "end.life_loss: trois vies apres la deuxieme perte")
	End.perdre_une_vie(t)
	h.eq(t.vies, 2, "end.life_loss: deux vies apres la troisieme perte")
	End.perdre_une_vie(t)
	h.eq(t.vies, 1, "end.life_loss: une vie apres la quatrieme perte")
	End.perdre_une_vie(t)
	h.eq(t.vies, 0, "end.life_loss: zero vie apres la cinquieme perte")

	# LE MEME INVARIANT DANS LE MODE DU DEFI, sur sa propre longueur : trois crans, zero au
	# bout. Le decrement ne depend pas du mode — seule la hauteur d'ou l'on part en depend.
	var d = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.NORMAL})
	h.eq(d.vies, 3, "end.life_loss: trois vies au depart dans le mode du defi")
	End.perdre_une_vie(d)
	h.eq(d.vies, 2, "end.life_loss: deux vies apres la premiere perte du defi")
	End.perdre_une_vie(d)
	h.eq(d.vies, 1, "end.life_loss: une vie apres la deuxieme perte du defi")
	End.perdre_une_vie(d)
	h.eq(d.vies, 0, "end.life_loss: zero vie apres la troisieme perte du defi")
