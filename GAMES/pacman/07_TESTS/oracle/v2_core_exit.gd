# v2_core_exit.gd — ligne core.exit, capacite F67.
# Le jeu peut etre quitte proprement. En V2 la sortie est une ENTREE DE MENU (Quitter) :
# le defaut vise nommement est « Quitter inerte » — presente, activable, sans effet.
extends RefCounted

const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")


func run(h) -> void:
	var sess: Dictionary = Shell.session_initiale()

	# QUITTER : l'effet EXISTE et il est OBSERVABLE.
	var q: Dictionary = Shell.activer_titre(sess, Menu.Titre.QUITTER)
	h.eq(q["sortie"], true, "core.exit: Quitter demande la sortie")
	h.eq(Shell.CODE_SORTIE, 0, "core.exit: le code de sortie est nul")
	h.eq(RuntimeLoop.CODE_SORTIE, 0, "core.exit: le runtime sort avec le meme code")

	# LES AUTRES ENTREES ne sortent pas : la sortie est bien portee par UNE entree.
	var sorties: int = 0
	for entree in Menu.ENTREES_TITRE:
		if Shell.activer_titre(sess, entree)["sortie"]:
			sorties += 1
	h.eq(sorties, 1, "core.exit: exactement une entree demande la sortie")

	# L'INTENTION DE RETOUR depuis le titre demande aussi la sortie.
	var r: Dictionary = Shell.appliquer_intention(sess, Intents.Intention.RETOUR)
	h.eq(r["sortie"], true, "core.exit: l'intention de retour depuis le titre sort")
	var en_partie: Dictionary = Shell.activer_titre(sess, Menu.Titre.JOUER)["session"]
	h.eq(Shell.appliquer_intention(en_partie, Intents.Intention.RETOUR)["sortie"], false,
		"core.exit: elle ne sort pas depuis la partie")

	# LA TOUCHE de sortie reste reconnue par le canal public.
	h.eq(InputAdapter.est_sortie(KEY_ESCAPE), true, "core.exit: echap demande la sortie")
	h.eq(InputAdapter.est_sortie(KEY_R), false, "core.exit: la relance n'est pas la sortie")
	h.eq(InputAdapter.est_sortie(KEY_UP), false, "core.exit: une direction n'est pas la sortie")
	h.ok(InputAdapter.CMD_SORTIE != InputAdapter.CMD_RELANCE, "core.exit: sortie et relance sont distinctes")
