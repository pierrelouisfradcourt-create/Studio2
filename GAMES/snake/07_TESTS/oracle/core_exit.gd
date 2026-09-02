# core_exit.gd — oracle de la ligne core.exit. SceneTree headless : la sortie demandee
# termine le processus avec un code EXACTEMENT 0 (constate par la disparition du process,
# jamais supposee). Cet oracle EST le process : il quitte lui-meme avec Exit.CODE_SORTIE et
# emet d'abord son recu. Le lecteur externe (node) lit l'EXIT_CODE reel du process.
# Sortie : "FORGE_ORACLE core_exit {json}", exit = Exit.CODE_SORTIE.
extends SceneTree

const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")

func _initialize() -> void:
	var fails: Array = []
	if Exit.CODE_SORTIE != 0:
		fails.append("code de sortie != 0")
	if not Exit.est_sortie(IA.CMD_SORTIE):
		fails.append("commande sortie non reconnue")
	# La commande sortie a bien un effet observable etiquete.
	if Exit.etiquette_effet(IA.traduire_keycode(KEY_ESCAPE)) != "processus_termine":
		fails.append("effet de la commande sortie absent")
	print("FORGE_ORACLE core_exit " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "code": Exit.CODE_SORTIE}))
	# Termine reellement avec le code declare : le lecteur verifie EXIT_CODE == 0.
	quit(Exit.CODE_SORTIE if fails.is_empty() else 1)
