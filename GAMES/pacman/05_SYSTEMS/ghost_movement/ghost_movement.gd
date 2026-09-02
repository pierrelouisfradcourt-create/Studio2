# ghost_movement.gd — algorithme de deplacement COMMUN aux quatre fantomes
# (lignes ghosts.intersection_choice, ghosts.frightened_draw, ghosts.cadence,
# ghosts.cadence_from_level).
#
# V2 : la carte est RECUE en argument, et la CADENCE prend la valeur du parametre de
# progression du niveau courant, PASSEE EN ARGUMENT — jamais lue dans une table indexee
# par niveau, ce qui rendrait l'ajout d'un niveau dependant de ce fichier.
#
# Les fantomes ne different QUE par leur cible : ce fichier ne connait aucun nom de
# fantome, seulement un index et une cible.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Rng = preload("res://05_SYSTEMS/rng/rng.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


# Cadence declaree (lignes ghosts.cadence, ghosts.cadence_from_level). CONTRAINTE DURE :
# un fantome est TOUJOURS strictement plus lent que Pac-Man, qui avance a chaque tick.
# En poursuite/dispersion il saute exactement un tick sur `periode` ; en Effraye il ne
# bouge qu'un tick sur P.CADENCE_EFFRAYE_PERIODE (ratio 0,50).
# `periode` est la valeur du parametre de progression du niveau courant : elle ARRIVE,
# elle n'est jamais cherchee. Une valeur non superieure a 1 retombe sur le repli declare
# dans le bloc de parametres, faute de quoi le fantome cesserait d'etre plus lent.
static func periode_effective(periode: int) -> int:
	if periode <= 1:
		return P.CADENCE_FANTOME_PERIODE
	return periode


static func bouge_ce_tick(tick: int, effraye: bool, periode: int) -> bool:
	if effraye:
		return tick % P.CADENCE_EFFRAYE_PERIODE == 0
	return tick % periode_effective(periode) != 0


# Sorties candidates a une case : les directions praticables, DEMI-TOUR EXCLU. Un
# cul-de-sac (aucune candidate) autorise le demi-tour — sinon le fantome serait fige.
static func sorties_candidates(carte, position: Vector2i, direction: Vector2i) -> Array:
	var demi_tour: Vector2i = Chase.inverser(direction)
	var candidates: Array = []
	for d in Maze.DIRECTIONS:
		if d == demi_tour:
			continue
		if carte.praticable(carte.case_suivante(position, d)):
			candidates.append(d)
	if candidates.is_empty() and carte.praticable(carte.case_suivante(position, demi_tour)):
		candidates.append(demi_tour)
	return candidates


# Choix a une intersection (ligne ghosts.intersection_choice) : la sortie dont la case
# est la PLUS PROCHE de la cible pour la mesure unique de ghost_targeting. Egalites
# departagees par l'ORDRE DECLARE de maze.DIRECTIONS (haut, gauche, bas, droite).
static func choisir_direction(carte, position: Vector2i, direction: Vector2i, cible: Vector2i) -> Vector2i:
	var candidates: Array = sorties_candidates(carte, position, direction)
	if candidates.is_empty():
		return direction
	var meilleure: Vector2i = candidates[0]
	var meilleure_d: int = Targeting.distance(carte.case_suivante(position, meilleure), cible)
	for i in range(1, candidates.size()):
		var d: Vector2i = candidates[i]
		var dist: int = Targeting.distance(carte.case_suivante(position, d), cible)
		if dist < meilleure_d:
			meilleure_d = dist
			meilleure = d
	return meilleure


# Tirage en etat Effraye (ligne ghosts.frightened_draw) : la direction est tiree parmi
# les sorties praticables AU MOYEN DU GENERATEUR SEEDE — unique source d'indeterminisme
# du jeu, donc integralement rejouable.
static func tirer_direction(carte, position: Vector2i, direction: Vector2i, etat_rng: int) -> Dictionary:
	var candidates: Array = sorties_candidates(carte, position, direction)
	if candidates.is_empty():
		return {"direction": direction, "etat_rng": etat_rng}
	var tirage: Dictionary = Rng.tirer(etat_rng, candidates.size())
	return {"direction": candidates[tirage["valeur"]], "etat_rng": tirage["etat"]}


# Cible d'un fantome selon son etat expose. En Effraye aucune cible n'est calculee : la
# direction est tiree, jamais dirigee.
static func cible_du_fantome(index: int, mode: int, s) -> Vector2i:
	if mode == Chase.Mode.DISPERSION:
		return Targeting.cible_dispersion(s.carte, index)
	if mode == Chase.Mode.POURSUITE:
		return Targeting.cible_poursuite(s.carte, index, s.pac, s.pac_dir, s.fantomes)
	return s.fantomes[index]


# Deplace TOUS les fantomes sortis de la maison, dans l'ordre fixe des index.
static func pas(s) -> void:
	for i in range(s.fantomes.size()):
		if not s.dehors[i]:
			continue
		var effraye: bool = s.effrayes[i]
		if not bouge_ce_tick(s.ticks, effraye, s.cadence_fantome):
			continue
		var position: Vector2i = s.fantomes[i]
		var direction: Vector2i = s.dirs_fantomes[i]
		if effraye:
			var tirage: Dictionary = tirer_direction(s.carte, position, direction, s.rng_etat)
			direction = tirage["direction"]
			s.rng_etat = tirage["etat_rng"]
		else:
			direction = choisir_direction(s.carte, position, direction, cible_du_fantome(i, s.etats_fantomes[i], s))
		s.dirs_fantomes[i] = direction
		var suivante: Vector2i = s.carte.case_suivante(position, direction)
		if s.carte.praticable(suivante):
			s.fantomes[i] = suivante


# Inversion de direction de chaque fantome hors maison au tick de bascule
# (ligne chase.switch_reversal — realisation du geste, decision prise par chase_state).
static func inverser_tous(s) -> void:
	for i in range(s.fantomes.size()):
		if s.dehors[i]:
			s.dirs_fantomes[i] = Chase.inverser(s.dirs_fantomes[i])
