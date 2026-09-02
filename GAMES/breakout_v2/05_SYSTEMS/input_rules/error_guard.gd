# error_guard.gd — ligne core.error_handling. Absorbe les entrees HORS DOMAINE avant
# qu'elles n'atteignent l'etat : une action inconnue est normalisee en AUCUNE, jamais une
# exception, jamais un etat invalide. RefCounted, pur. Capacite : error.guard.
extends RefCounted

const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

# Normalise une action arbitraire : si elle appartient au vocabulaire ferme, elle passe ;
# sinon elle est absorbee en AUCUNE (immobile). Aucune entree hors domaine ne casse l'etat.
static func normaliser(action: int) -> int:
	if InputRules.est_action(action):
		return action
	return InputRules.AUCUNE
