# exit.gd — lignes core.exit + runtime.exit_observable. Sortie observable du produit :
# la commande de sortie termine le processus avec un code EXACTEMENT 0 ; et CHAQUE
# commande exposee (direction, pause, reprise, relance, sortie) produit un changement
# LISIBLE dans l'etat expose. La classification est PURE et testable en headless ; le
# pilote de scene applique reellement quit(). RefCounted.
extends RefCounted

const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Pause = preload("res://05_SYSTEMS/game_state/pause.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

# Code de sortie du processus quand la sortie est demandee : EXACTEMENT 0.
const CODE_SORTIE: int = 0

# Une commande est-elle la commande de sortie ?
static func est_sortie(commande: String) -> bool:
	return commande == IA.CMD_SORTIE

# Effet observable d'une commande de vocabulaire ferme sur l'etat expose. Renvoie une
# etiquette non vide DECRIVANT le changement lisible — jamais un no-op silencieux. Sert
# l'oracle runtime.exit_observable : chaque commande exposee a bien un effet.
#   direction (dir non nulle) : "direction_demandee"
#   pause / reprise           : "bascule_pause"
#   relance                   : "etat_reinitialise"
#   sortie                    : "processus_termine"
static func etiquette_effet(action: Dictionary) -> String:
	if action.get("kind") == "direction":
		return "direction_demandee"
	if action.get("kind") == "commande":
		match action.get("commande"):
			IA.CMD_PAUSE:
				return "bascule_pause"
			IA.CMD_RELANCE:
				return "etat_reinitialise"
			IA.CMD_SORTIE:
				return "processus_termine"
	return ""
