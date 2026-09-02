# v2_core_restart.gd — ligne core.restart, capacite F74.
# Une nouvelle partie peut etre relancee dans un etat initial propre. En V2 la relance
# est atteignable DEPUIS LA PAUSE (Recommencer) : reconstruction integrale, aucune
# valeur de la partie interrompue ne survit.
extends RefCounted

const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var jeu = sess["partie"]
	for _t in range(25):
		jeu = Loop.step(jeu, jeu.carte.DEPART_DIRECTION)["etat"]
	jeu.score = 999
	sess["partie"] = jeu
	var pause: Dictionary = Sess.mettre_en_pause(sess)

	var relance: Dictionary = Shell.activer_pause(pause, Menu.Pause.RECOMMENCER)["session"]
	h.eq(relance["partie"].ticks, 0, "core.restart: la relance repart du tick 0")
	h.eq(relance["partie"].score, 0, "core.restart: le score repart de zero")
	h.eq(relance["partie"].consommees, 0, "core.restart: les collectibles repartent")
	h.eq(int(relance["app"]), App.Etat.PARTIE, "core.restart: l'application est en partie")

	# RECONSTRUCTION INTEGRALE : aucune valeur ne fuit, champ par champ.
	var neuf = Restart.relancer(Shell.carte(0), Shell.GRAINE_INITIALE, Shell.cadence(0), sess["reglages"])
	h.eq(relance["partie"].egal_profond(neuf), true, "core.restart: etat egal a une partie neuve")
	h.eq(Restart.aucune_fuite(relance["partie"], Shell.carte(0), Shell.GRAINE_INITIALE,
		Shell.cadence(0), sess["reglages"]), true, "core.restart: aucune fuite detectee")

	# CONTRE-EPREUVE : le detecteur REFUSE un etat pollue, champ par champ.
	for champ in ["score", "consommees", "ticks", "horloge", "rang_capture"]:
		var pollue = Restart.relancer(Shell.carte(0), Shell.GRAINE_INITIALE, Shell.cadence(0), sess["reglages"])
		pollue.set(champ, 1)
		h.eq(Restart.aucune_fuite(pollue, Shell.carte(0), Shell.GRAINE_INITIALE,
			Shell.cadence(0), sess["reglages"]), false,
			"core.restart: une fuite du champ %s est detectee" % champ)

	# LA PARTIE RELANCEE est reellement jouable.
	var apres = Loop.step(relance["partie"], relance["partie"].carte.DEPART_DIRECTION)["etat"]
	h.eq(apres.ticks, 1, "core.restart: la partie relancee avance")
	h.eq(apres.statut, State.Statut.EN_COURS, "core.restart: elle reste jouable")
