extends Control
## Barre de vie (héros, Gardien). Quand la valeur baisse, la vie perdue reste visible un instant
## en clair (« fantôme ») puis se vide, et le cadre tressaille : on VOIT le coup.
## Portage de `updateGhost` / `bar` de src/render/hud.mjs. `marques` : fractions repérées d'un
## trait (les seuils de phase du Gardien).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const TENUE := 0.35 # s pendant lesquelles la vie perdue reste entière
const VIDANGE := 1.2 # fraction de la barre vidée par seconde ensuite
const CHOC := 0.25 # s de tressaillement du cadre
const GONFLE := 2.0 # px ajoutés au cadre au moment du coup

var marques: Array = []

var _frac := -1.0
var _fantome := -1.0
var _tenue := 0.0
var _choc := 0.0
var _couleur := Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func poser(frac: float, couleur: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if _frac >= 0.0 and frac < _frac - 0.0005:
		_tenue = TENUE
		_choc = CHOC
	if _fantome < 0.0 or frac >= _fantome:
		_fantome = frac
	if frac != _frac or couleur != _couleur:
		queue_redraw()
	_frac = frac
	_couleur = couleur

## Nouvelle partie, nouveau Gardien : la barre repart sans fantôme.
func reinitialiser() -> void:
	_frac = -1.0
	_fantome = -1.0
	_choc = 0.0

func _process(delta: float) -> void:
	if _choc > 0.0:
		_choc = maxf(0.0, _choc - delta)
		queue_redraw()
	if _fantome > _frac:
		if _tenue > 0.0:
			_tenue -= delta
		else:
			_fantome = maxf(_frac, _fantome - VIDANGE * delta)
			queue_redraw()

func _draw() -> void:
	var k := _choc / CHOC
	var cadre := Rect2(Vector2.ZERO, size).grow(GONFLE * k)
	var encre: Color = Couleurs.UI["void"]
	draw_rect(cadre, Couleurs.PAL.hpBack)
	_bande(cadre, _fantome, Color(Couleurs.PAL.hero, 0.8))
	_bande(cadre, _frac, _couleur.lerp(Couleurs.PAL.hero, 0.6 * k))
	for m in marques:
		var x: float = cadre.position.x + cadre.size.x * float(m)
		draw_line(Vector2(x, cadre.position.y), Vector2(x, cadre.end.y), Color(encre, 0.85), 2.0)
	draw_rect(cadre, Color(encre, 0.8).lerp(Couleurs.PAL.hero, k), false, 2.0)

func _bande(cadre: Rect2, frac: float, col: Color) -> void:
	if frac > 0.0:
		draw_rect(Rect2(cadre.position, Vector2(cadre.size.x * frac, cadre.size.y)), col)
