# frightened_slowdown.gd — ralentissement en etat Effraye (ligne harness.frightened_slowdown).
# Sur une fenetre declaree en etat Effraye, le nombre de cases parcourues par CHAQUE
# fantome est STRICTEMENT inferieur a celui parcouru par Pac-Man.
#
# Fixture de MESURE : les quatre fantomes sont poses loin de Pac-Man, dehors et
# Effrayes ; Pac-Man longe le couloir droit du bas. Les eloigner n'est pas un
# arrangement de confort : un contact renverrait un fantome en maison et arreterait son
# deplacement, ce qui fausserait le comptage qu'on cherche a etablir.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const GRAINE_MESURE: int = 17
const LIGNE_COULOIR: int = 32
const PAC_X: int = 2
const FENETRE: int = P.FENETRE_MESURE_ECART_TICKS
const PLACES_ELOIGNEES: Array = [
	Vector2i(1, 4), Vector2i(26, 4), Vector2i(6, 8), Vector2i(21, 8),
]


static func fixture(carte) -> Object:
	var s = State.initial(carte, GRAINE_MESURE)
	s.pac = Vector2i(PAC_X, LIGNE_COULOIR)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	for i in range(s.fantomes.size()):
		s.fantomes[i] = PLACES_ELOIGNEES[i]
		s.dirs_fantomes[i] = Maze.GAUCHE
		s.dehors[i] = true
		s.sorties_maison[i] = 0
	Chase.armer_effraye(s)
	# La fenetre mesuree doit tenir ENTIEREMENT dans l'etat Effraye.
	s.effraye_restant = FENETRE + P.DUREE_EFFRAYE_TICKS
	Chase.rafraichir_etats(s)
	return s


static func mesurer(carte) -> Dictionary:
	var s = fixture(carte)
	var pas_joueur: int = 0
	var pas_fantomes: Array = [0, 0, 0, 0]
	var tous_effrayes: bool = true
	for _t in range(FENETRE):
		var pac_avant: Vector2i = s.pac
		var avant: Array = s.fantomes.duplicate()
		s = Loop.step(s, Maze.DROITE)["etat"]
		if s.pac != pac_avant:
			pas_joueur += 1
		for i in range(s.fantomes.size()):
			if s.fantomes[i] != avant[i]:
				pas_fantomes[i] += 1
			if s.etats_fantomes[i] != Chase.Mode.EFFRAYE:
				tous_effrayes = false
	return {
		"fenetre": FENETRE,
		"pas_joueur": pas_joueur,
		"pas_fantomes": pas_fantomes,
		"tous_effrayes": tous_effrayes,
	}


# Nombre de fantomes qui n'ont PAS parcouru strictement moins de cases que Pac-Man.
static func fantomes_non_ralentis(mesure: Dictionary) -> int:
	var n: int = 0
	for pas in mesure["pas_fantomes"]:
		if not (pas < mesure["pas_joueur"]):
			n += 1
	return n
