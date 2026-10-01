extends Control
## Les commandes TACTILES : le joystick flottant et les cinq boutons, DESSINÉS aux positions que
## donne la vue Entrees (`interface_tactile()`, en pixels du viewport). Ce nœud ne lit aucun
## toucher : la vue Entrees s'en charge. Portage de `drawTouchControls` (src/render/hud.mjs).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Etats = preload("res://jeu/interface/etat_commandes.gd")
const COURSE := 58.0 # rayon de la base du joystick
const POUCE := 26.0
const DEGAGEMENT := 24.0 # px autour du groupe de boutons

@onready var _boutons := {"attack": $Attaque, "dash": $Dash, "skill": $Competence, "super": $Super, "gadget": $Gadget}

var _manette := {}
var _coin := Vector2.INF

func actualiser(game: Dictionary, ui: Dictionary) -> void:
	_manette = ui.get("stick", {})
	_coin = Vector2.INF
	for b in ui.get("buttons", []):
		var bouton: Control = _boutons.get(b.id)
		if bouton == null:
			continue
		var glisse := Vector2(b.get("dx", 0.0), b.get("dy", 0.0)) if D6Js.truthy(b.get("dragging")) else Vector2.ZERO
		bouton.placer(Vector2(b.x, b.y), b.r)
		bouton.montrer(Etats.etat(game, b.id), D6Js.truthy(b.get("pressed")), glisse)
		_coin = _coin.min(Vector2(b.x - b.r, b.y - b.r))
	queue_redraw()

## Coin haut-gauche du groupe de boutons : rien d'autre ne doit s'y poser.
func coin() -> Vector2:
	return _coin - Vector2.ONE * DEGAGEMENT if _coin.is_finite() else size

func _draw() -> void:
	if not D6Js.truthy(_manette.get("active")):
		return
	var blanc: Color = Couleurs.PAL.text
	var base := Vector2(_manette.baseX, _manette.baseY)
	var encre: Color = Couleurs.UI["void"]
	var pouce := Vector2(_manette.knobX, _manette.knobY)
	# Cerne sombre puis trait clair : le joystick se lit sur un sol clair comme sur un sol noir.
	draw_circle(base, COURSE, Color(encre, 0.22), true, -1.0, true)
	draw_arc(base, COURSE + 0.5, 0.0, TAU, 48, Color(encre, 0.45), 4.5, true)
	draw_arc(base, COURSE, 0.0, TAU, 48, Color(blanc, 0.45), 2.0, true)
	draw_circle(pouce, POUCE + 1.5, Color(encre, 0.45), true, -1.0, true)
	draw_circle(pouce, POUCE, Color(blanc, 0.5), true, -1.0, true)
