# exit_stop.test.gd — ligne runtime.exit_observable. Code de sortie EXACTEMENT 0 ; chaque
# commande du vocabulaire ferme produit un effet LISIBLE (jamais une commande inerte — defaut
# Pong 2026-07-27).
extends RefCounted

const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")

func run(h) -> void:
	# --- code de sortie ---
	h.eq(Exit.CODE_SORTIE, 0, "code de sortie = EXACTEMENT 0")
	h.eq(Exit.est_sortie(IA.CMD_SORTIE), true, "commande sortie reconnue")
	h.eq(Exit.est_sortie(IA.CMD_RELANCE), false, "relance n'est pas une sortie")
	h.eq(Exit.est_sortie("bruit"), false, "commande inconnue n'est pas une sortie")

	# --- chaque commande a un effet observable NON VIDE (jamais inerte) ---
	h.ok(Exit.etiquette_effet({"kind": "direction", "dir": 1}) != "", "direction -> effet observable")
	h.eq(Exit.etiquette_effet({"kind": "commande", "commande": IA.CMD_RELANCE}), "etat_reinitialise", "relance -> effet lisible")
	h.eq(Exit.etiquette_effet({"kind": "commande", "commande": IA.CMD_SORTIE}), "processus_termine", "sortie -> effet lisible")
	# une non-action reste vide (pas de faux effet).
	h.eq(Exit.etiquette_effet({"kind": "aucun"}), "", "aucune action -> pas d'effet fantome")
