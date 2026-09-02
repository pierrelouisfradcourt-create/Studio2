# chase_thresholds.gd — assertion des SIX seuils de l'horloge (ligne harness.chase_thresholds).
# Releve l'etat EXPOSE juste avant le seuil, exactement au seuil et juste apres.
#
# Protocole de mesure DECLARE : les quatre fantomes sont maintenus dans la maison
# pendant toute la fenetre, et aucune entree n'est injectee. Sans cet isolement, une
# perte de vie remettrait l'horloge a son premier segment au milieu de la mesure et le
# releve ne mesurerait plus l'horloge, mais la survie du joueur.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")

const GRAINE_MESURE: int = 3
const MARGE_APRES_DERNIER_SEUIL: int = 5


# Fixture d'isolement : partie normale, fantomes retenus dans la maison au-dela de la
# fenetre mesuree. C'est une fixture de MESURE, jamais un etat force pour faire passer
# une condition de victoire.
static func fixture(carte, fenetre: int) -> Object:
	var s = State.initial(carte, GRAINE_MESURE)
	for i in range(s.fantomes.size()):
		s.dehors[i] = false
		s.fantomes[i] = carte.PLACES_MAISON[i]
		s.sorties_maison[i] = fenetre + 1
	return s


static func fenetre_requise() -> int:
	var seuils: Array = Chase.seuils()
	return seuils[seuils.size() - 1] + MARGE_APRES_DERNIER_SEUIL


# Trace des releves exposes, un par tick, sur la fenetre requise.
static func releves(carte) -> Array:
	var fenetre: int = fenetre_requise()
	var s = fixture(carte, fenetre)
	var trace: Array = [Observable.projeter(s)]
	for _t in range(fenetre):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		trace.append(Observable.projeter(s))
	return trace


# Mode attendu a un instant d'horloge, lu de la source unique (chase_state).
static func mode_attendu(horloge: int) -> String:
	return Observable.nom_mode(Chase.mode_global(horloge))


# Pour chacun des six seuils : le releve juste avant, exactement au seuil, juste apres.
# Rend une liste de constats, jamais un booleen agrege.
static func constats(carte) -> Array:
	var trace: Array = releves(carte)
	var sortie: Array = []
	for seuil in Chase.seuils():
		sortie.append({
			"seuil": seuil,
			"avant_lu": trace[seuil - 1]["mode"],
			"avant_attendu": mode_attendu(seuil - 1),
			"au_lu": trace[seuil]["mode"],
			"au_attendu": mode_attendu(seuil),
			"apres_lu": trace[seuil + 1]["mode"],
			"apres_attendu": mode_attendu(seuil + 1),
		})
	return sortie


# Aucun retour en dispersion apres le sixieme seuil.
static func dispersion_apres_dernier_seuil(trace: Array) -> int:
	var seuils: Array = Chase.seuils()
	var dernier: int = seuils[seuils.size() - 1]
	var n: int = 0
	for i in range(dernier, trace.size()):
		if trace[i]["mode"] == "DISPERSION":
			n += 1
	return n
