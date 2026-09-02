# harness_dash_measurement.gd — LES QUATRE GRANDEURS DU DASH, DANS LES DEUX CONDITIONS
# (lignes harness.dash_four_quantities, dash.declared_effects).
#
# Releve les quatre grandeurs touchees par le dash — vitesse du joueur, delai avant le
# dash suivant, comportement face aux murs, comportement face aux fantomes — AVEC et
# SANS dash, puis CONFRONTE chaque releve a la declaration de dash.declared_effects.
#
# Une grandeur annoncee MODIFIEE et mesuree identique est REQUALIFIEE, jamais laissee
# telle quelle : c'est le sens de `ecarts_a_la_declaration`.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const GRAINE: int = 21
const FENETRE: int = 12


# COULOIR DE MESURE : le plus long segment horizontal praticable de la carte, trouve
# par lecture de la carte elle-meme. Sans un couloir plus long que la fenetre, les deux
# conditions buteraient au meme mur et la vitesse mesuree serait identique par ACCIDENT
# de topologie — la mesure ne dirait alors rien du dash. Aucune coordonnee de carte
# n'est ecrite ici : le couloir est DERIVE, donc valable sur toute carte.
static func couloir_le_plus_long(carte) -> Dictionary:
	var meilleur: Dictionary = {"depart": Vector2i(0, 0), "longueur": 0}
	for y in range(carte.HAUTEUR):
		var debut: int = -1
		var n: int = 0
		for x in range(carte.LARGEUR + 1):
			var libre: bool = x < carte.LARGEUR and carte.praticable(Vector2i(x, y))
			if libre:
				if debut < 0:
					debut = x
				n += 1
			else:
				if n > meilleur["longueur"]:
					meilleur = {"depart": Vector2i(debut, y), "longueur": n}
				debut = -1
				n = 0
	return meilleur


# Fixture : partie normale, fantomes retenus dans la maison sur toute la fenetre, joueur
# pose au debut du plus long couloir. Les retenir n'est pas un confort : un contact
# renverrait Pac-Man au depart et le comptage de cases ne mesurerait plus la vitesse,
# mais la survie.
static func fixture(carte, dash_actif: bool) -> Object:
	var s = State.initial(carte, GRAINE, 0, {"dash_actif": dash_actif})
	var couloir: Dictionary = couloir_le_plus_long(carte)
	s.pac = couloir["depart"]
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	for i in range(s.fantomes.size()):
		s.dehors[i] = false
		s.fantomes[i] = carte.PLACES_MAISON[i]
		s.sorties_maison[i] = FENETRE + 1
	return s


# GRANDEUR 1 — vitesse du joueur : cases parcourues sur la fenetre, dash demande a
# chaque tick ou jamais.
static func cases_parcourues(carte, avec_dash: bool) -> int:
	var s = fixture(carte, true)
	var parcourues: int = 0
	for _t in range(FENETRE):
		var avant: Vector2i = s.pac
		s = Loop.step(s, Maze.DROITE, avec_dash)["etat"]
		parcourues += Maze.distance(avant, s.pac)
	return parcourues


# GRANDEUR 2 — delai avant le dash suivant : valeur de la recharge relevee au tick qui
# suit un dash.
static func delai_apres_dash(carte) -> int:
	var s = fixture(carte, true)
	s = Loop.step(s, carte.DEPART_DIRECTION, true)["etat"]
	return Observable.projeter(s)["dash_recharge"]


static func delai_sans_dash(carte) -> int:
	var s = fixture(carte, true)
	s = Loop.step(s, carte.DEPART_DIRECTION, false)["etat"]
	return Observable.projeter(s)["dash_recharge"]


# GRANDEUR 3 — comportement face aux murs : case atteinte en poussant contre un mur,
# avec et sans budget de dash. STRUCTURELLEMENT identique : la meme regle de butee est
# appliquee a chaque case du budget.
static func case_contre_mur(carte, budget: int) -> Vector2i:
	var depart: Vector2i = carte.DEPART_PACMAN
	# Direction dont la case suivante N'EST PAS praticable : un vrai mur, pas un couloir.
	for d in Maze.DIRECTIONS:
		if not carte.praticable(carte.case_suivante(depart, d)):
			return Player.avancer_budget(carte, depart, d, budget)
	return depart


# GRANDEUR 4 — comportement face aux fantomes : le module de contact ne connait pas le
# dash. Le constat est STRUCTUREL — un deplacement de dash traverse le meme test.
static func contacts_detectes(carte, budget: int) -> int:
	var depart: Vector2i = carte.DEPART_PACMAN
	var arrivee: Vector2i = Player.avancer_budget(carte, depart, carte.DEPART_DIRECTION, budget)
	var touches: Array = Contacts.detecter(
		depart, arrivee, [arrivee, depart, depart, depart], [arrivee, depart, depart, depart],
		[true, true, true, true])
	return touches.size()


# RELEVE des quatre grandeurs dans les DEUX conditions. Le nombre de grandeurs SANS
# releve vaut exactement 0 : chacune a une valeur des deux cotes.
static func releves(carte) -> Dictionary:
	return {
		"vitesse_joueur": {
			"avec": cases_parcourues(carte, true),
			"sans": cases_parcourues(carte, false),
		},
		"delai_avant_dash": {
			"avec": delai_apres_dash(carte),
			"sans": delai_sans_dash(carte),
		},
		"comportement_murs": {
			"avec": case_contre_mur(carte, P.PAS_DASH),
			"sans": case_contre_mur(carte, P.PAS_NORMAL),
		},
		"comportement_fantomes": {
			"avec": contacts_detectes(carte, P.PAS_DASH),
			"sans": contacts_detectes(carte, P.PAS_NORMAL),
		},
	}


static func grandeurs_sans_releve(carte) -> int:
	var r: Dictionary = releves(carte)
	var n: int = 0
	for g in Dash.GRANDEURS:
		if not r.has(g):
			n += 1
			continue
		if not r[g].has("avec") or not r[g].has("sans"):
			n += 1
	return n


# ECARTS A LA DECLARATION : une grandeur declaree MODIFIEE doit presenter deux valeurs
# DISTINCTES, une grandeur declaree INCHANGEE deux valeurs EGALES. Tout ecart est
# NOMME — c'est ce qui requalifie une promesse trop forte au lieu de la laisser passer.
static func ecarts_a_la_declaration(carte) -> Array:
	var r: Dictionary = releves(carte)
	var sortie: Array = []
	for g in Dash.GRANDEURS:
		var avec = r[g]["avec"]
		var sans = r[g]["sans"]
		var attendu: String = Dash.EFFETS_DECLARES[g]
		if attendu == Dash.MODIFIE and avec == sans:
			sortie.append(g)
		if attendu == Dash.INCHANGE and avec != sans:
			sortie.append(g)
	return sortie


static func mesurer(carte) -> Dictionary:
	return {
		"releves": releves(carte),
		"grandeurs_sans_releve": grandeurs_sans_releve(carte),
		"ecarts_a_la_declaration": ecarts_a_la_declaration(carte),
	}
