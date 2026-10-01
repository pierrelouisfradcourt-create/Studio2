extends TextureRect
## Vignette rouge de danger : un éclair quand le héros est touché, un battement tant qu'il est
## sous 30 % de vie. Portage de `drawVignettes` (src/render/hud.mjs) ; le dégradé est fabriqué
## une fois (aucune image importée), seule son opacité change.

const Degrades = preload("res://jeu/interface/degrades.gd")
const SEUIL := 0.3 # part de vie sous laquelle la vignette bat
const DECLIN := 2.5 # par seconde

var _partie
var _coup := 0.0
var _temps := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = Degrades.vignette()
	modulate.a = 0.0

func brancher(partie) -> void:
	_partie = partie
	partie.evenements.connect(_sur_evenements)

func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		if ev.type == "playerHurt":
			_coup = 1.0

func _process(delta: float) -> void:
	var game = _partie.game if _partie != null else null
	if game == null:
		modulate.a = 0.0
		return
	_temps += delta
	_coup = maxf(0.0, _coup - delta * DECLIN)
	var p: Dictionary = game.player
	var bas: bool = p.hp / p.maxHp < SEUIL and p.get("state") != "dead"
	modulate.a = clampf(maxf(_coup * 0.45, 0.22 + 0.1 * sin(_temps * 5.0) if bas else 0.0), 0.0, 1.0)
