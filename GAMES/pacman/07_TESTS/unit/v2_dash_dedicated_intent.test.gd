# v2_dash_dedicated_intent.test.gd — ligne dash.dedicated_intent, capacite F83.
# Le dash se declenche sur son intention DEDIEE, distincte des quatre directions :
# aucune direction ne dashe, aucun dash ne deplace par le canal des directions.
extends RefCounted

const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	h.eq(Dash.INTENTION_DEDIEE, Intents.Intention.DASH, "dash.intent: l'intention dediee est le dash")
	h.eq(Dash.est_demande(Intents.Intention.DASH), true, "dash.intent: l'intention dediee declenche")
	var directions_qui_dashent: int = 0
	for d in Intents.DIRECTIONS:
		if Dash.est_demande(d):
			directions_qui_dashent += 1
	h.eq(directions_qui_dashent, 0, "dash.intent: aucune direction ne dashe")
	h.eq(Dash.est_demande(Intents.Intention.PAUSE), false, "dash.intent: la pause ne dashe pas")
	h.eq(Dash.est_demande(Intents.Intention.AUCUNE), false, "dash.intent: l'absence d'intention ne dashe pas")

	# LE DASH PRODUIT UN BUDGET, jamais un deplacement.
	var jeu = State.initial(Maze, 11)
	h.eq(Dash.disponible(jeu), true, "dash.intent: le dash est disponible au depart")
	var avant: Vector2i = jeu.pac
	var budget: int = Dash.appliquer(jeu, true)
	h.eq(budget, P.PAS_DASH, "dash.intent: la demande rend le budget de dash")
	h.eq(jeu.pac, avant, "dash.intent: le module ne deplace pas le joueur")
	h.eq(jeu.dash_recharge, P.RECHARGE_DASH_TICKS, "dash.intent: la recharge est armee")
	h.eq(Dash.disponible(jeu), false, "dash.intent: le dash n'est plus disponible")

	# Sans demande : budget normal.
	var jeu2 = State.initial(Maze, 11)
	h.eq(Dash.appliquer(jeu2, false), P.PAS_NORMAL, "dash.intent: sans demande, budget normal")
	h.eq(jeu2.dash_recharge, 0, "dash.intent: aucune recharge sans dash")

	# PAR LE TICK : une direction seule ne fait jamais avancer de PAS_DASH cases.
	var sans = State.initial(Maze, 11)
	var avec = State.initial(Maze, 11)
	var d0: Vector2i = sans.pac
	sans = Loop.step_intentions(sans, [Intents.Intention.GAUCHE])["etat"]
	var pas_direction: int = MazeClass.distance(d0, sans.pac)
	avec = Loop.step_intentions(avec, [Intents.Intention.GAUCHE, Intents.Intention.DASH])["etat"]
	var pas_dash: int = MazeClass.distance(d0, avec.pac)
	h.eq(pas_direction, P.PAS_NORMAL, "dash.intent: une direction seule avance d'une case")
	h.gt(pas_dash, pas_direction, "dash.intent: l'intention dediee avance strictement plus")
	h.eq(pas_dash, P.PAS_DASH, "dash.intent: elle avance exactement du budget declare")
	# --- GATE MUTATION : le SENS de la recharge -------------------------------------
	# Le compteur de recharge DECROIT tick apres tick. Un compteur qui croit rendrait
	# le dash indisponible pour toujours, sans qu'aucune egalite ne le voie.
	var recharge = State.initial(Maze, 11)
	recharge.dash_recharge = 5
	Dash.appliquer(recharge, false)
	h.eq(recharge.dash_recharge, 4, "dash.intent: la recharge decroit d'exactement un tick")
	Dash.appliquer(recharge, false)
	h.eq(recharge.dash_recharge, 3, "dash.intent: et encore d'un au tick suivant")
	h.lt(recharge.dash_recharge, 5, "dash.intent: elle decroit, elle ne croit pas")

	# A ZERO elle ne descend pas plus bas, et le dash redevient disponible.
	recharge.dash_recharge = 0
	Dash.appliquer(recharge, false)
	h.eq(recharge.dash_recharge, 0, "dash.intent: la recharge ne passe pas sous zero")
	h.eq(Dash.disponible(recharge), true, "dash.intent: recharge ecoulee, le dash revient")
	recharge.dash_recharge = 1
	h.eq(Dash.disponible(recharge), false, "dash.intent: a un tick pres, il ne l'est pas encore")
