class_name D6Lab
extends RefCounted
## Portage de src/sim/lab.mjs.
## LABORATOIRE DU FEEL — D5, D8, D9 restent OUVERTES : le prototype permet de les comparer.
##
##   D5  lab.dashStrike    : quand une attaque devient FRAPPE DE DASH
##         fin        — attaquer dans la fin du dash (dernier 45 %) coupe la ruée, ou juste après
##         toutDash   — attaquer à N'IMPORTE QUEL moment du dash coupe la ruée en frappe
##         apresDash  — la ruée va toujours au bout ; seule une attaque juste APRÈS devient frappe
##   D8  lab.hitstop       : gel d'impact
##         global     — toute la scène se fige (projectiles, autres ennemis compris)
##         local      — seuls l'attaquant et la ou les cibles se figent ; le reste du monde continue
##   D9  lab.comboMobility : mobilité pendant le combo
##         ancre      — 20 % de la vitesse, annulations tardives : chaque coup engage
##         mobile     — 50 %, annulations actuelles (réglage de référence)
##         fluide     — 75 %, annulations très tôt : on danse en frappant
##
## Chaque variante écrit des clés ordinaires du tuning de la partie : le code de combat ne
## connaît pas le labo. La variante par défaut de chaque axe redonne EXACTEMENT les valeurs
## de config.mjs (aucun test ni réglage existant ne bouge tant qu'on ne choisit rien).
## La table LAB_AXES est lue dans D6Data.tables().lab.LAB_AXES.

static func _axes() -> Dictionary:
	return D6Data.tables().lab.LAB_AXES

static func _set_path(obj: Dictionary, path: String, value) -> void:
	var keys := path.split(".")
	var o: Dictionary = obj
	for i in keys.size() - 1:
		o = o[keys[i]]
	o[keys[keys.size() - 1]] = value

## tuning.lab?.[axis] : la variante choisie, null si le labo ou l'axe manque.
static func _choice(tuning: Dictionary, axis: String):
	var lab = tuning.get("lab")
	return lab.get(axis) if lab is Dictionary else null

## Applique les variantes choisies (tuning.lab) au tuning de la partie. Idempotent. Un axe absent
## ou une variante inconnue retombe sur la RÉFÉRENCE de l'axe (jamais sur la 1re option listée :
## pour D9, ce serait « Ancré », pas les valeurs d'origine).
static func apply_lab(tuning: Dictionary) -> Dictionary:
	var axes := _axes()
	for axis in axes:
		var def: Dictionary = axes[axis]
		var opt = def.options.get(_choice(tuning, axis))
		if opt == null:
			opt = def.options[def.reference]
		for path in opt.set:
			_set_path(tuning, path, opt.set[path])
	return tuning

## Change une variante en cours de partie (pause → Labo) ; rend false si inconnue.
static func set_lab(tuning: Dictionary, axis, choice) -> bool:
	var def = _axes().get(axis)
	if def == null or def.options.get(choice) == null:
		return false
	if not (tuning.get("lab") is Dictionary):
		tuning.lab = {}
	tuning.lab[axis] = choice
	apply_lab(tuning)
	return true

static func lab_summary(tuning: Dictionary) -> Array:
	var axes := _axes()
	var out: Array = []
	for axis in axes:
		var def: Dictionary = axes[axis]
		var chosen = _choice(tuning, axis)
		var choice = chosen if def.options.get(chosen) != null else def.reference
		out.append({"axis": axis, "label": def.label, "choice": choice, "choiceLabel": def.options[choice].label})
	return out
