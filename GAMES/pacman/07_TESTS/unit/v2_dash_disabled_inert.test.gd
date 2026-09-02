# v2_dash_disabled_inert.test.gd — ligne dash.disabled_inert, capacite F84.
# Dash DESACTIVE : la commande continue d'exister mais ne laisse AUCUNE trace dans
# l'etat — ni deplacement, ni compteur de recharge, ni marqueur. Propriete d'EGALITE
# STRICTE de traces, pas une absence d'effet visible.
extends RefCounted

const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))

const FENETRE: int = 30


func _trace(avec_appuis: bool, dash_actif: bool) -> Array:
	var s = State.initial(Maze, 13, 0, {"dash_actif": dash_actif})
	var suite: Array = [Observable.projeter(s)]
	for _t in range(FENETRE):
		var intentions: Array = [Intents.Intention.GAUCHE]
		if avec_appuis:
			intentions.append(Intents.Intention.DASH)
		s = Loop.step_intentions(s, intentions)["etat"]
		suite.append(Observable.projeter(s))
	return suite


func _divergences(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return 1
	var n: int = 0
	for i in range(a.size()):
		for cle in Observable.CLES:
			if a[i].get(cle) != b[i].get(cle):
				n += 1
	return n


func run(h) -> void:
	# DASH DESACTIVE : les deux traces sont STRICTEMENT EGALES.
	var avec: Array = _trace(true, false)
	var sans: Array = _trace(false, false)
	h.eq(avec.size(), FENETRE + 1, "dash.inert: la fenetre est reellement parcourue")
	h.eq(_divergences(avec, sans), 0, "dash.inert: 0 divergence entre appuyer et ne pas appuyer")

	# CONTRE-EPREUVE : dash ACTIVE, le comparateur DETECTE bien une difference — sans
	# quoi « 0 divergence » ne prouverait rien.
	var avec_actif: Array = _trace(true, true)
	var sans_actif: Array = _trace(false, true)
	h.gt(_divergences(avec_actif, sans_actif), 0, "dash.inert: le comparateur detecte une difference")

	# AUCUN MARQUEUR : la recharge reste a 0 sur toute la fenetre, dash desactive.
	var recharges: int = 0
	for releve in avec:
		if int(releve["dash_recharge"]) != 0:
			recharges += 1
	h.eq(recharges, 0, "dash.inert: aucun compteur de recharge ne bouge")

	# LE MODULE lui-meme est inerte : aucun champ ecrit.
	var s = State.initial(Maze, 13, 0, {"dash_actif": false})
	var copie = s.clone()
	h.eq(Dash.appliquer(s, true), P.PAS_NORMAL, "dash.inert: le budget reste normal")
	h.eq(s.egal_profond(copie), true, "dash.inert: aucun champ de l'etat n'est touche")
	h.eq(Dash.disponible(s), false, "dash.inert: le dash desactive n'est jamais disponible")
