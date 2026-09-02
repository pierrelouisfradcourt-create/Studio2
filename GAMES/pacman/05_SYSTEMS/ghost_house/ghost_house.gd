# ghost_house.gd — maison centrale (lignes house.release_schedule, house.return_captured,
# house.positions_from_state_map).
#
# V2 : les positions de maison — centre, sortie, places — sont lues sur la CARTE PORTEE
# PAR L'ETAT, jamais sur une constante globale ; a la bascule de niveau, ce sont celles
# de la carte suivante.
#
# UNIQUE PROPRIETAIRE des positions de maison : aucun autre module ne place un fantome
# dans la maison ni ne l'en sort.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const DELAIS_SORTIE: Array = P.DELAIS_SORTIE_MAISON
const DELAI_RETOUR: int = P.DELAI_RETOUR_MAISON


# Place de repos d'un fantome dans la maison de la CARTE DONNEE (le rouge est deja
# dehors au tick 0).
static func place(carte, index: int) -> Vector2i:
	return carte.PLACES_MAISON[index]


# Etat de depart de la maison : exactement UN fantome dehors, et c'est le rouge (index 0).
static func etat_initial(carte) -> Dictionary:
	var positions: Array = []
	var dehors: Array = []
	var sorties: Array = []
	for i in range(carte.PLACES_MAISON.size()):
		positions.append(place(carte, i))
		dehors.append(DELAIS_SORTIE[i] == 0)
		sorties.append(DELAIS_SORTIE[i])
	return {"positions": positions, "dehors": dehors, "sorties": sorties}


# Sortie de la maison aux ticks declares et STRICTEMENT CROISSANTS.
static func mettre_a_jour(s) -> void:
	for i in range(s.fantomes.size()):
		if s.dehors[i]:
			continue
		if s.ticks >= s.sorties_maison[i]:
			s.dehors[i] = true
			s.fantomes[i] = s.carte.SORTIE_MAISON
			s.dirs_fantomes[i] = Maze.GAUCHE


# Renvoi d'un fantome CAPTURE : il retourne dans la maison, sort de l'etat Effraye, et
# le compteur de vies n'est PAS touche ici.
static func renvoyer(s, index: int) -> void:
	s.fantomes[index] = place(s.carte, index)
	s.dirs_fantomes[index] = Maze.GAUCHE
	s.dehors[index] = false
	s.effrayes[index] = false
	s.sorties_maison[index] = s.ticks + DELAI_RETOUR
	Chase.rafraichir_etats(s)


# Remise a l'etat de depart apres une perte de vie : le rouge dehors, les autres dedans
# avec leurs delais declares, comptes a partir du tick courant.
static func reinitialiser(s) -> void:
	for i in range(s.fantomes.size()):
		s.fantomes[i] = place(s.carte, i)
		s.dirs_fantomes[i] = Maze.GAUCHE
		s.dehors[i] = DELAIS_SORTIE[i] == 0
		s.sorties_maison[i] = s.ticks + DELAIS_SORTIE[i]
		s.effrayes[i] = false
