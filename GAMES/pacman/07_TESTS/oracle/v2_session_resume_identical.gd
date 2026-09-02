# v2_session_resume_identical.gd — ligne session.resume_identical, capacite F73.
# Reprendre RESTITUE l'etat GELE sans le modifier : son effet correct est de NE RIEN
# CHANGER, puis de laisser le temps de jeu repartir. La propriete est une EGALITE
# STRICTE d'etats, ce qui interdit une reconstruction « equivalente ».
extends RefCounted

const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")


func run(h) -> void:
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var jeu = sess["partie"]
	for _t in range(25):
		jeu = Loop.step(jeu, jeu.carte.DEPART_DIRECTION)["etat"]
	sess["partie"] = jeu
	var gele = jeu.clone()

	# PAUSE : l'etat est gele, pas modifie.
	var pause: Dictionary = Sess.mettre_en_pause(sess)
	h.eq(int(pause["app"]), App.Etat.PAUSE, "session.resume: le menu pause est actif")
	h.eq(pause["partie"].egal_profond(gele), true, "session.resume: l'etat gele est intact")

	# REPRENDRE : egalite STRICTE avec l'etat gele, champ par champ.
	var reprise: Dictionary = Shell.activer_pause(pause, Menu.Pause.REPRENDRE)["session"]
	h.eq(int(reprise["app"]), App.Etat.PARTIE, "session.resume: l'application repart en partie")
	h.eq(reprise["partie"].egal_profond(gele), true, "session.resume: etat strictement egal a l'etat gele")
	h.eq(Observable.egaux(Observable.projeter(reprise["partie"]), Observable.projeter(gele)), true,
		"session.resume: le releve observable est identique")
	h.eq(reprise["partie"].ticks, gele.ticks, "session.resume: le compteur n'a pas bouge")
	h.eq(reprise["partie"].score, gele.score, "session.resume: le score n'a pas bouge")

	# PUIS LA PARTIE REPART.
	var apres = Loop.step(reprise["partie"], reprise["partie"].carte.DEPART_DIRECTION)["etat"]
	h.eq(apres.ticks, gele.ticks + 1, "session.resume: le temps de jeu repart")
	h.eq(apres.statut, State.Statut.EN_COURS, "session.resume: la partie reste jouable")

	# CONTRE-EPREUVE : le comparateur d'etats DETECTE une reconstruction « equivalente ».
	var reconstruit = State.initial(gele.carte, 1)
	h.eq(reconstruit.egal_profond(gele), false, "session.resume: une reconstruction n'est pas l'etat gele")
