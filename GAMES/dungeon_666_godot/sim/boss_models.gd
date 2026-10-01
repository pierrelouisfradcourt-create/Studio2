class_name D6BossModels
extends RefCounted
## Portage de src/sim/boss_models.mjs.
## Registre des MODÈLES de Gardien ajoutés (un fichier par modèle : sim/boss_<modèle>.gd).
## Chaque modèle : { byPhase: {"1": [...], "2": [...], "3": [...]}, patterns: {nom: Callable(game, e, d, dt, speed)},
## rest?(game, e, d, dt, speed), tick?(game, e, d, dt), available?(game, e, d, nom) }.
## La clé = kind de l'ennemi = clé de tuning.boss (boss_data.mjs).

static var _extra = null

## EXTRA_BOSS_MODELS (construit une fois, PARTAGÉ : ne pas le modifier).
static func extra_boss_models() -> Dictionary:
	if _extra == null:
		_extra = {
			"cerbere": D6BossCerbere.model(),
			"minos": D6BossMinos.model(),
			"colosse": D6BossColosse.model(),
		}
	return _extra
