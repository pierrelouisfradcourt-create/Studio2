# exit.gd — ligne core.exit. Sortie observable : la commande de sortie termine le processus
# avec un code EXACTEMENT 0 ; et CHAQUE commande exposee (direction, relance, sortie) produit
# un effet LISIBLE (jamais une commande inerte — defaut Pong 2026-07-27). Classification PURE,
# testable en headless ; le pilote de scene applique reellement quit(). RefCounted.
extends RefCounted

const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")

# Code de sortie du processus quand la sortie est demandee : EXACTEMENT 0.
const CODE_SORTIE: int = 0

static func est_sortie(commande: String) -> bool:
	return commande == IA.CMD_SORTIE

# Effet observable d'une action du vocabulaire ferme : etiquette NON VIDE decrivant le
# changement lisible — jamais un no-op silencieux.
static func etiquette_effet(action: Dictionary) -> String:
	if action.get("kind") == "direction":
		return "raquette_deplacee"
	if action.get("kind") == "commande":
		match action.get("commande"):
			IA.CMD_RELANCE:
				return "etat_reinitialise"
			IA.CMD_SORTIE:
				return "processus_termine"
	return ""
