# v2_loop_tick_order_with_dash.test.gd — ligne loop.tick_order_with_dash, capacite F83.
# L'ORDRE du tick est FIGE et DECLARE, budget de dash compris. Le tick ne mute JAMAIS
# l'etat d'entree : il produit un nouvel etat.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	h.eq(Loop.ORDRE, ["entree", "horloge", "budget_dash", "pac", "fantomes", "consommation", "contacts", "statut"],
		"loop.ordre: ordre fige et declare, budget de dash compris")
	h.eq(Loop.ORDRE.size(), 8, "loop.ordre: huit etapes declarees")
	h.eq(Loop.ORDRE.find("budget_dash"), 2, "loop.ordre: le budget vient apres l'horloge")
	h.lt(Loop.ORDRE.find("budget_dash"), Loop.ORDRE.find("pac"), "loop.ordre: et avant le deplacement")

	# NE MUTE JAMAIS l'entree.
	var jeu = State.initial(Maze, 15)
	var copie = jeu.clone()
	var sortie: Dictionary = Loop.step_intentions(jeu, [Intents.Intention.GAUCHE, Intents.Intention.DASH])
	h.eq(jeu.egal_profond(copie), true, "loop.ordre: l'etat d'entree est intact")
	h.eq(sortie["etat"].ticks, 1, "loop.ordre: le nouvel etat a avance d'un tick")
	h.ok(sortie["etat"].pac != jeu.pac, "loop.ordre: le nouvel etat a bouge")

	# LES INTENTIONS entrent par la porte unique.
	var par_intention: Dictionary = Loop.step_intentions(State.initial(Maze, 15), [Intents.Intention.GAUCHE])
	var par_vecteur: Dictionary = Loop.step(State.initial(Maze, 15), MazeClass.GAUCHE)
	h.eq(Observable.egaux(Observable.projeter(par_intention["etat"]), Observable.projeter(par_vecteur["etat"])), true,
		"loop.ordre: intention et direction empruntent le meme chemin")

	# DASH DESACTIVE : la trace est strictement egale avec ou sans appui sur le dash.
	var sans = State.initial(Maze, 15, 0, {"dash_actif": false})
	var avec = State.initial(Maze, 15, 0, {"dash_actif": false})
	for _t in range(10):
		sans = Loop.step_intentions(sans, [Intents.Intention.GAUCHE])["etat"]
		avec = Loop.step_intentions(avec, [Intents.Intention.GAUCHE, Intents.Intention.DASH])["etat"]
	h.eq(Observable.egaux(Observable.projeter(sans), Observable.projeter(avec)), true,
		"loop.ordre: dash desactive, la trace est identique")

	# UNE PARTIE TERMINEE ne rejoue pas de tick.
	var fini = State.initial(Maze, 15)
	fini.statut = State.Statut.GAGNE
	var apres = Loop.step(fini, MazeClass.GAUCHE)["etat"]
	h.eq(apres.ticks, 0, "loop.ordre: aucun tick apres un statut terminal")
	# --- GATE MUTATION : les VALEURS PAR DEFAUT du tick ------------------------------
	# Un tick appele sans demande explicite ne dashe PAS et n'ouvre PAS de menu. Si le
	# defaut basculait, tout tick consommerait un dash et emettrait un son de pause,
	# sans qu'aucune egalite d'etat ne le voie.
	var defaut = State.initial(Maze, 15)
	var apres_defaut: Dictionary = Loop.step(defaut, MazeClass.GAUCHE)
	h.eq(apres_defaut["etat"].dash_recharge, 0,
		"loop.ordre: un tick sans demande de dash n'arme aucune recharge")
	h.eq(apres_defaut["evenements_sonores"].has("son_pause"), false,
		"loop.ordre: un tick sans ouverture de menu n'emet aucun son de pause")

	# CONTRE-EPREUVE : demandes explicites, les deux effets apparaissent.
	var avec_dash: Dictionary = Loop.step(State.initial(Maze, 15), MazeClass.GAUCHE, true)
	h.gt(avec_dash["etat"].dash_recharge, 0, "loop.ordre: une demande explicite arme la recharge")
	var avec_menu: Dictionary = Loop.step(State.initial(Maze, 15), MazeClass.GAUCHE, false, true)
	h.eq(avec_menu["evenements_sonores"].has("son_pause"), true,
		"loop.ordre: une ouverture explicite emet le son de pause")

	# MEME PROPRIETE par le canal des intentions.
	var par_intentions: Dictionary = Loop.step_intentions(State.initial(Maze, 15), [])
	h.eq(par_intentions["evenements_sonores"].has("son_pause"), false,
		"loop.ordre: le canal des intentions ne suppose aucune ouverture de menu")
	h.eq(par_intentions["etat"].dash_recharge, 0,
		"loop.ordre: ni aucune demande de dash")
