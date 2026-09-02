# core_exit.gd — oracle (bot_action) de la ligne core.exit. Code de sortie EXACTEMENT 0 ;
# chaque commande du vocabulaire ferme produit un effet LISIBLE (jamais inerte).
extends SceneTree

const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")

func _initialize() -> void:
	var fails: Array = []
	if Exit.CODE_SORTIE != 0:
		fails.append("code de sortie != 0")
	if not Exit.est_sortie(IA.CMD_SORTIE):
		fails.append("commande sortie non reconnue")
	# Chaque commande du vocabulaire ferme a un effet observable NON VIDE.
	var commandes := [
		{"kind": "direction", "dir": 1},
		{"kind": "commande", "commande": IA.CMD_RELANCE},
		{"kind": "commande", "commande": IA.CMD_SORTIE},
	]
	for c in commandes:
		if Exit.etiquette_effet(c) == "":
			fails.append("commande sans effet observable: %s" % str(c))
	print("ORACLE core_exit: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
