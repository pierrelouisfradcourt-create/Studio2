# flee_gap.gd — ecart creuse par Pac-Man fuyant en couloir droit (ligne harness.flee_gap).
#
# L'exigence porte sur le SIGNE de l'inegalite observable, pas sur la valeur 0,95 : ce
# module mesure que la distance est STRICTEMENT plus grande a la fin de la fenetre qu'a
# son debut, ce qui etablit « le fantome est plus lent » sans postuler de combien.
#
# CORRECTION M3 (red-team s6) : sur grille DISCRETE a 19/20, le fantome ne perd une case
# que toutes les CADENCE_FANTOME_PERIODE ticks. La fenetre de mesure vaut donc
# P.FENETRE_MESURE_ECART_TICKS — plus court, l'ecart mesure serait 0 et l'assertion
# serait fausse.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const GRAINE_MESURE: int = 13
const LIGNE_COULOIR: int = 32
const PAC_X: int = 2
const ROUGE_X: int = 1
const FENETRE: int = P.FENETRE_MESURE_ECART_TICKS


static func fixture(carte) -> Object:
	var s = State.initial(carte, GRAINE_MESURE)
	s.pac = Vector2i(PAC_X, LIGNE_COULOIR)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	s.fantomes[Targeting.ROUGE] = Vector2i(ROUGE_X, LIGNE_COULOIR)
	s.dirs_fantomes[Targeting.ROUGE] = Maze.DROITE
	s.dehors[Targeting.ROUGE] = true
	for i in range(1, s.fantomes.size()):
		s.dehors[i] = false
		s.fantomes[i] = carte.PLACES_MAISON[i]
		s.sorties_maison[i] = FENETRE + 1
	return s


# Pac-Man fuit en s'eloignant : la direction DROITE est emise a chaque tick sur le
# canal d'entree public, jamais ecrite dans l'etat.
static func mesurer(carte) -> Dictionary:
	var s = fixture(carte)
	var debut: int = Targeting.distance(s.pac, s.fantomes[Targeting.ROUGE])
	var pas_joueur: int = 0
	var pas_fantome: int = 0
	for _t in range(FENETRE):
		var pac_avant: Vector2i = s.pac
		var rouge_avant: Vector2i = s.fantomes[Targeting.ROUGE]
		s = Loop.step(s, Maze.DROITE)["etat"]
		if s.pac != pac_avant:
			pas_joueur += 1
		if s.fantomes[Targeting.ROUGE] != rouge_avant:
			pas_fantome += 1
	var fin: int = Targeting.distance(s.pac, s.fantomes[Targeting.ROUGE])
	return {
		"fenetre": FENETRE,
		"distance_debut": debut,
		"distance_fin": fin,
		"pas_joueur": pas_joueur,
		"pas_fantome": pas_fantome,
	}
