extends Control
## La BARRE D'EXPÉRIENCE de la classe : fine, de la teinte froide du héros (l'or reste l'or, le
## rouge reste la vie). Elle sert au HUD (sous la vie), à l'écran de mort (où la part GAGNÉE dans
## la descente se détache, plus claire, et se remplit sous les yeux) et au Grimoire.
## Elle ne lit rien : on lui pose une part (0..1) ; `eclater()` la fait briller un instant (niveau passé).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ECLAT := 0.7 # s de brillance après un niveau passé
const REMPLISSAGE := 0.9 # s pour que la part gagnée se remplisse (écran de mort)
const ASSOMBRI := 0.35 # la part d'avant la descente, par rapport à la part gagnée

var _frac := 0.0
var _depuis := -1.0 # part d'où le gain est parti (-1 : pas de gain à montrer)
var _montre := 0.0 # part dessinée (elle rattrape `_frac`)
var _eclat := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## `frac` : la part acquise du niveau en cours (0..1). `depuis` (0..frac) : la part qu'on avait
## AVANT — ce qui est entre les deux est le gain, plus clair, et se remplit à vue.
func poser(frac: float, depuis: float = -1.0) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if is_equal_approx(frac, _frac) and is_equal_approx(depuis, _depuis):
		return
	_frac = frac
	_depuis = minf(depuis, frac)
	_montre = maxf(0.0, _depuis) if depuis >= 0.0 else frac
	set_process(_montre < _frac or _eclat > 0.0)
	queue_redraw()

## La part posée, et celle d'où part le gain (pour les essais).
func part() -> float:
	return _frac

func depuis() -> float:
	return _depuis

## Un niveau vient d'être passé : la barre brille un instant.
func eclater() -> void:
	_eclat = ECLAT
	set_process(true)
	queue_redraw()

func brille() -> bool:
	return _eclat > 0.0

func _process(delta: float) -> void:
	_eclat = maxf(0.0, _eclat - delta)
	_montre = minf(_frac, _montre + delta / REMPLISSAGE)
	set_process(_montre < _frac or _eclat > 0.0)
	queue_redraw()

func _draw() -> void:
	var cadre := Rect2(Vector2.ZERO, size)
	var teinte: Color = Couleurs.PAL.heroCape
	var k := _eclat / ECLAT
	draw_rect(cadre.grow(1.0), Color(Couleurs.UI["void"], 0.8))
	draw_rect(cadre, Couleurs.PAL.hpBack)
	var avant := _depuis if _depuis >= 0.0 else 0.0
	if avant > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * avant, size.y)), teinte.darkened(ASSOMBRI))
	if _montre > avant:
		draw_rect(Rect2(Vector2(size.x * avant, 0.0), Vector2(size.x * (_montre - avant), size.y)), teinte.lerp(Couleurs.PAL.hero, 0.25 + 0.6 * k))
	if k > 0.0:
		draw_rect(cadre.grow(1.0 + 2.0 * k), Color(Couleurs.PAL.gold, k), false, 1.5)
