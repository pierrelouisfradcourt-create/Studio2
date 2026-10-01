class_name D6Foes
extends RefCounted
## Portage de src/sim/foes.mjs.
## Registre des archétypes d'ennemis AJOUTÉS hors de enemies (un fichier par archétype :
## sim/foe_<archétype>.gd).
## Chaque entrée : { kind, ai: Callable(game, e, def, dt), melee?: bool, shooter?: bool }.
## Les données (PV, vitesses, télégraphes…) vivent dans tuning.enemies[kind].

static var _extra_foes = null

## EXTRA_FOES.
static func extra_foes() -> Array:
	if _extra_foes == null:
		_extra_foes = [D6FoePyromancer.model(), D6FoeNecromancer.model(), D6FoePavois.model(), D6FoeStalker.model(), D6FoeBanner.model()]
	return _extra_foes
