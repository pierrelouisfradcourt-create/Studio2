extends RefCounted
## Le doigt sur de vrais Control. Le projet convertit le PREMIER doigt en souris, pas les
## suivants : avec le pouce gauche resté sur le joystick, un Button n'entend pas le second doigt.
## Ce module rend aux panneaux le geste du web (src/ui/dom.mjs, onActivate) : un bouton s'active
## au RELÂCHER du même doigt, s'il est resté dessus. Un glissé fait défiler le panneau, ou règle
## une réglette, sans rien activer.

const SEUIL_GLISSE := 12.0 # unités d'écran : au-delà, le doigt glisse (il ne tape plus)

var _prises := {} # index du doigt -> {cible, depart, glisse, regle, defilement}

## Un doigt se pose : on retient le bouton ou la réglette qu'il touche sous `racine`.
func appuyer(racine: Control, defilement: ScrollContainer, index: int, pos: Vector2) -> void:
	_prises[index] = {"cible": _sous(racine, defilement, pos), "depart": pos, "glisse": false, "regle": false, "defilement": defilement}

## Le doigt glisse de `relatif` (unités du panneau) : réglette, ou défilement vertical.
func glisser(index: int, pos: Vector2, relatif: Vector2) -> void:
	var prise = _prises.get(index)
	if prise == null:
		return
	if not prise.glisse and pos.distance_to(prise.depart) > SEUIL_GLISSE:
		var ecart: Vector2 = pos - prise.depart
		prise.glisse = true
		prise.regle = prise.cible is Range and absf(ecart.x) > absf(ecart.y)
	if not prise.glisse:
		return
	if prise.regle and is_instance_valid(prise.cible):
		_regler(prise.cible, pos)
	elif is_instance_valid(prise.defilement):
		prise.defilement.scroll_vertical -= int(round(relatif.y))

## Le doigt se lève : rend le bouton à activer (null si le doigt a glissé, est sorti du
## bouton, ou si le geste est annulé). Un tap sur une réglette la règle à cet endroit.
func relacher(index: int, pos: Vector2, annule: bool) -> BaseButton:
	var prise = _prises.get(index)
	_prises.erase(index)
	if prise == null or annule or prise.glisse or not is_instance_valid(prise.cible):
		return null
	var cible: Control = prise.cible
	if not _contient(cible, pos):
		return null
	if cible is Range:
		_regler(cible, pos)
		return null
	return cible if cible is BaseButton and not cible.disabled else null

func oublier() -> void:
	_prises.clear()

static func _contient(c: Control, pos: Vector2) -> bool:
	var local: Vector2 = c.get_global_transform().affine_inverse() * pos
	return Rect2(Vector2.ZERO, c.size).has_point(local)

## Le bouton ou la réglette visible le plus au-dessus sous le point (le dernier dans l'arbre).
static func _sous(racine: Control, defilement: ScrollContainer, pos: Vector2) -> Control:
	var trouve: Control = null
	var dans_fenetre := defilement == null or _contient(defilement, pos)
	for n in racine.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is BaseButton or c is Range) or c is ScrollBar or not c.is_visible_in_tree():
			continue
		if c is BaseButton and c.disabled:
			continue
		if defilement != null and defilement.is_ancestor_of(c) and not dans_fenetre:
			continue
		if _contient(c, pos):
			trouve = c
	return trouve

static func _regler(reglette: Range, pos: Vector2) -> void:
	var local: Vector2 = reglette.get_global_transform().affine_inverse() * pos
	var part := clampf(local.x / maxf(1.0, reglette.size.x), 0.0, 1.0)
	reglette.value = reglette.min_value + part * (reglette.max_value - reglette.min_value)
