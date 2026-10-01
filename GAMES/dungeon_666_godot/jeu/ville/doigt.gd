extends Node
## Le DOIGT dans la Ville, quand le projet N'ÉMULE PAS la souris par le tactile
## (`input_devices/pointing/emulate_mouse_from_touch = false`) : sans émulation, un Button ne
## répond pas au toucher et un ScrollContainer ne défile pas. Ce nœud rend alors au premier doigt
## posé le comportement attendu d'un menu :
##   - toucher puis relâcher sans glisser = un appui (clic de souris synthétique, au même point) ;
##   - glisser = faire défiler la liste (et l'appui en cours est abandonné).
## Quand l'émulation est active (réglage du projet au 2026-10-01), il ne fait RIEN : le moteur
## s'en charge (boutons et cartes laissent passer la souris jusqu'au ScrollContainer, qui défile
## au doigt et annule l'appui en cours), et chaque appui compterait double.

const SEUIL := 12.0 # px de référence avant qu'un toucher devienne un glissement
const HORS_ECRAN := Vector2(-1000.0, -1000.0)

## La liste à faire défiler au doigt.
@export var defilement: ScrollContainer
## La Ville n'écoute le doigt que lorsqu'elle est affichée.
var actif := false

var _doigt := -1
var _depart := Vector2.ZERO
var _glisse := false

func _input(ev: InputEvent) -> void:
	if not actif or Input.emulate_mouse_from_touch:
		return
	if ev is InputEventScreenTouch:
		_toucher(ev)
	elif ev is InputEventScreenDrag and ev.index == _doigt:
		_glisser(ev)

func _toucher(ev: InputEventScreenTouch) -> void:
	if ev.pressed and _doigt < 0:
		_doigt = ev.index
		_depart = ev.position
		_glisse = false
		_souris.call_deferred(true, ev.position)
	elif not ev.pressed and ev.index == _doigt:
		_doigt = -1
		if not _glisse:
			_souris.call_deferred(false, ev.position)

func _glisser(ev: InputEventScreenDrag) -> void:
	if not _glisse and ev.position.distance_to(_depart) > SEUIL:
		_glisse = true
		_souris.call_deferred(false, HORS_ECRAN) # relâché ailleurs : le bouton touché n'est pas pressé
	if _glisse and defilement != null:
		var echelle: float = defilement.get_global_transform_with_canvas().get_scale().y
		defilement.scroll_vertical -= int(roundf(ev.relative.y / maxf(0.01, echelle)))

## Bouton gauche de souris synthétique, envoyé à l'interface de cette fenêtre seulement.
func _souris(appui: bool, position: Vector2) -> void:
	var clic := InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = appui
	clic.position = position
	clic.global_position = position
	get_viewport().push_input(clic, true)
