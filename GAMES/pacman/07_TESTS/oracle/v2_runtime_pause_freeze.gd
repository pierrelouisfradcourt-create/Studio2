# v2_runtime_pause_freeze.gd — ligne runtime.pause_freeze, capacite F71.
# Le temps du moteur n'est converti en appels au tick QUE lorsque l'etat d'application
# l'autorise. Pendant la pause, AUCUN tick n'est execute : l'etat releve a l'ouverture
# et l'etat releve N ticks plus tard sont le MEME etat, et non deux etats voisins.
extends RefCounted

const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const N_TICKS: int = 40


func run(h) -> void:
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var jeu = sess["partie"]
	for _t in range(20):
		jeu = Loop.step(jeu, jeu.carte.DEPART_DIRECTION)["etat"]
	sess["partie"] = jeu
	var pause: Dictionary = Sess.mettre_en_pause(sess)
	var a_l_ouverture: Dictionary = Observable.projeter(pause["partie"])

	# LE CADENCEUR ne rend AUCUN tick tant que l'etat d'application ne l'autorise pas.
	var accum: float = 0.0
	var ticks: int = 0
	for _t in range(N_TICKS):
		var r: Dictionary = RuntimeLoop.avancer(accum, P.PERIODE_TICK_MS, P.PERIODE_TICK_MS,
			not RuntimeLoop.tick_autorise(pause))
		accum = r["accumulateur"]
		ticks += int(r["ticks"])
	h.eq(ticks, 0, "runtime.pause: 0 tick execute sur %d trames de pause" % N_TICKS)
	h.eq(accum, 0.0, "runtime.pause: l'accumulateur ne s'accumule pas non plus")

	# CHAMP PAR CHAMP : l'etat releve N ticks plus tard est le MEME etat.
	var n_ticks_plus_tard: Dictionary = Observable.projeter(pause["partie"])
	h.eq(Observable.egaux(a_l_ouverture, n_ticks_plus_tard), true, "runtime.pause: le releve est identique")
	for cle in ["pac", "score", "vies", "restantes", "horloge", "fantomes", "tick"]:
		h.eq(n_ticks_plus_tard[cle], a_l_ouverture[cle], "runtime.pause: champ %s inchange" % cle)

	# CONTRE-EPREUVE : hors pause, le MEME cadenceur rend bien des ticks.
	var en_partie: Dictionary = Sess.reprendre(pause)
	var r2: Dictionary = RuntimeLoop.avancer(0.0, P.PERIODE_TICK_MS, P.PERIODE_TICK_MS,
		not RuntimeLoop.tick_autorise(en_partie))
	h.eq(int(r2["ticks"]), 1, "runtime.pause: hors pause, le cadenceur rend un tick")
	h.eq(RuntimeLoop.tick_autorise(en_partie), true, "runtime.pause: le tick redevient autorise")

	# LA PAUSE gele par ABSENCE D'APPEL : le tick lui-meme n'a aucun drapeau de pause.
	var f := FileAccess.open("res://05_SYSTEMS/game_loop/game_loop.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("app_state"), false, "runtime.pause: la boucle de jeu ignore l'etat d'application")
	h.eq(texte.contains("PAUSE"), false, "runtime.pause: elle ne porte aucun drapeau de pause")
