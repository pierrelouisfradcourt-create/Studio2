class_name D6FoeBanner
extends RefCounted
## Portage de src/sim/foe_banner.mjs.
## SOUTIEN — « Porte-étendard » (kind 'banner'). Données : tuning.enemies.banner.
##
## Il n'attaque JAMAIS. Tant qu'il est debout (ni mort, ni étourdi), les autres ennemis à moins de
## `auraRadius` de lui ne prennent que `wardMult` des dégâts (D6FoeDefense.ward_of, lu par
## combat.damage_enemy). L'aura se voit : alerte INOFFENSIVE permanente (e.tele harmless: true, de
## rayon auraRadius) ; elle disparaît dès qu'il est étourdi (enemies efface e.tele), et la
## protection avec elle.
##
## Un seul état, chase : il suit la mêlée à distance (keepDistance : se rapproche au-delà de
## preferredDist + approachSlack, recule sous fleeDist, sinon tourne lentement autour du héros).
## Contre-jeu : traverser la mêlée pour le tuer d'abord (dash), ou entraîner le combat hors de
## l'aura — il est lent. Aucun dégât de contact, aucun dégât du tout.

static var _model = null

## BANNER : { kind, ai: Callable(game, e, def, dt) }.
static func model() -> Dictionary:
	if _model == null:
		_model = {"kind": "banner", "ai": _banner_ai}
	return _model

static func _banner_ai(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	if e.state != "chase":
		D6AiCommon.set_state(e, "chase")
	e.tele = {"shape": "circle", "r": def.auraRadius, "progress": 1.0, "harmless": true}
	var tp := D6AiCommon.to_player(game, e)
	D6AiCommon.keep_distance(game, e, def, tp, D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y), D6AiCommon.speed_of(game, e, def))
