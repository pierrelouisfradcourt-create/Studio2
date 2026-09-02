# v2_app_tick_gate.test.gd — ligne app.tick_gate, capacite F64.
# LE PREDICAT QUI FAIT FOI : le tick de partie est-il autorise a cet instant ? Unique
# autorite consultee par la boucle du runtime.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")


func run(h) -> void:
	# UN SEUL etat autorise le tick.
	var autorises: int = 0
	for e in App.ETATS_VALIDES:
		if App.tick_autorise(e):
			autorises += 1
	h.eq(autorises, 1, "app.tick_gate: un seul etat autorise le tick")
	h.eq(App.tick_autorise(App.Etat.PARTIE), true, "app.tick_gate: la partie autorise le tick")
	h.eq(App.tick_autorise(App.Etat.TITRE), false, "app.tick_gate: le titre ne l'autorise pas")
	h.eq(App.tick_autorise(App.Etat.PAUSE), false, "app.tick_gate: la pause ne l'autorise pas")
	h.eq(App.tick_autorise(App.Etat.CONTROLES), false, "app.tick_gate: les controles ne l'autorisent pas")
	h.eq(App.tick_autorise(App.Etat.OPTIONS), false, "app.tick_gate: les options ne l'autorisent pas")
	h.eq(App.tick_autorise(App.Etat.FIN), false, "app.tick_gate: la fin ne l'autorise pas")

	# A L'ECRAN TITRE : le compteur de ticks vaut exactement 0 parce qu'AUCUNE partie
	# n'existe — pas parce qu'un rendu la masque.
	var sess: Dictionary = Shell.session_initiale()
	h.eq(Sess.ticks_de_partie(sess), 0, "app.tick_gate: 0 tick de partie a l'ecran titre")
	h.eq(sess["partie"] == null, true, "app.tick_gate: aucune partie construite")
	h.eq(RuntimeLoop.tick_autorise(sess), false, "app.tick_gate: le runtime n'appelle aucun tick")

	# APRES Jouer : le tick devient autorise et le compteur progresse.
	var jouant: Dictionary = Shell.activer_titre(sess, Menu.Titre.JOUER)["session"]
	h.eq(RuntimeLoop.tick_autorise(jouant), true, "app.tick_gate: le tick est autorise en partie")
	h.eq(Sess.ticks_de_partie(jouant), 0, "app.tick_gate: la partie neuve part de 0")

	# EN PAUSE : le tick redevient interdit, la partie EXISTE toujours.
	var pause: Dictionary = Sess.mettre_en_pause(jouant)
	h.eq(RuntimeLoop.tick_autorise(pause), false, "app.tick_gate: aucun tick en pause")
	h.ok(pause["partie"] != null, "app.tick_gate: la partie existe toujours derriere la pause")
