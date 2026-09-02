# v2_session_restart_and_quit_to_title.gd — ligne session.restart_and_quit_to_title, F74.
# Recommencer reconstruit INTEGRALEMENT une partie neuve depuis la pause ; Menu principal
# abandonne la partie et fait quitter a l'application l'etat partie en cours.
extends RefCounted

const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")


func run(h) -> void:
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var jeu = sess["partie"]
	for _t in range(30):
		jeu = Loop.step(jeu, jeu.carte.DEPART_DIRECTION)["etat"]
	jeu.score = 4321
	sess["partie"] = jeu
	var pause: Dictionary = Sess.mettre_en_pause(sess)

	# RECOMMENCER : etat egal a l'etat de depart d'une partie NEUVE.
	var recommence: Dictionary = Shell.activer_pause(pause, Menu.Pause.RECOMMENCER)["session"]
	var neuf = State.initial(Shell.carte(0), Shell.GRAINE_INITIALE, Shell.cadence(0), sess["reglages"])
	h.eq(int(recommence["app"]), App.Etat.PARTIE, "session.restart: l'application est en partie")
	h.eq(recommence["partie"].egal_profond(neuf), true, "session.restart: etat egal a une partie neuve")
	h.eq(recommence["partie"].ticks, 0, "session.restart: compteur remis a zero")
	h.eq(recommence["partie"].score, 0, "session.restart: aucune valeur de la partie interrompue ne survit")
	h.ok(recommence["partie"].score != 4321, "session.restart: le score interrompu ne fuit pas")
	h.eq(recommence["partie"].niveau, State.PREMIER_NIVEAU, "session.restart: retour au premier niveau")

	# MENU PRINCIPAL : statut HORS PARTIE.
	var retour: Dictionary = Shell.activer_pause(pause, Menu.Pause.MENU_PRINCIPAL)["session"]
	h.eq(int(retour["app"]), App.Etat.TITRE, "session.restart: Menu principal ramene au titre")
	h.eq(retour["partie"] == null, true, "session.restart: la partie est abandonnee")
	h.eq(Sess.partie_en_cours(retour), false, "session.restart: aucune partie ne tourne")
	h.eq(Sess.ticks_de_partie(retour), 0, "session.restart: 0 tick de partie")
	h.eq(Sess.statut_de_partie(retour), Sess.AUCUN_STATUT, "session.restart: aucun statut de partie")

	# La partie GELEE n'a pas ete mutee par ces deux operations.
	h.eq(pause["partie"].score, 4321, "session.restart: l'etat gele n'a pas ete mute")
