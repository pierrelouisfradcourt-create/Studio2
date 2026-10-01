extends Control
## Flashs d'écran, sur le CanvasLayer d'Effets : un voile clair et bref (Super, bénédiction,
## Gardien qui s'enrage) et une vignette rouge sur les bords quand le héros est touché (tenue plus
## longtemps à sa mort). Portage de fx.flash / fx.hurtFlash et de drawVignettes
## (GAMES/dungeon_666/src/render/fx.mjs et hud.mjs). Aucune image : la vignette est un dégradé
## radial fabriqué au démarrage. Ne dessine rien au repos.

const Couleurs = preload("res://jeu/theme/couleurs.gd")

const VOILE := Color(1.0, 0.94, 0.86) # blanc chaud
const VOILE_ALPHA := 0.25 # opacité du voile pour une force de 1
const VOILE_DECLIN := 2.0 # par seconde
const BLESSURE_ALPHA := 0.4
const BLESSURE_DECLIN := 2.5
const MORT_DECLIN := 0.6
const VIGNETTE_DEBUT := 0.58 # part du demi-écran laissée intacte au centre

var _voile := 0.0
var _teinte := VOILE
var _blessure := 0.0
var _declin := BLESSURE_DECLIN
var _vignette: GradientTexture2D

func _init() -> void:
	# Dégradé radial fabriqué une fois (aucun fichier d'image) : transparent au centre, plein au bord.
	var degrade := Gradient.new()
	degrade.offsets = PackedFloat32Array([0.0, VIGNETTE_DEBUT, 1.0])
	degrade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color.WHITE])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = degrade
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.08, 0.5)
	_vignette.width = 64
	_vignette.height = 64

func actif() -> bool:
	return _voile > 0.0 or _blessure > 0.0

## Voile clair de force 0..1 (0,5 pour un Super, 0,35 pour une bénédiction).
func voile(force: float, teinte: Color = VOILE) -> void:
	if force >= _voile:
		_voile = force
		_teinte = teinte
	visible = true
	queue_redraw()

## Vignette rouge : le héros vient d'être touché (`mort` : elle s'attarde).
func blessure(mort: bool = false) -> void:
	_blessure = 1.0
	_declin = MORT_DECLIN if mort else BLESSURE_DECLIN
	visible = true
	queue_redraw()

func vider() -> void:
	_voile = 0.0
	_blessure = 0.0
	visible = false

func avancer(dt: float) -> void:
	if not visible:
		return
	_voile = maxf(0.0, _voile - dt * VOILE_DECLIN)
	_blessure = maxf(0.0, _blessure - dt * _declin)
	visible = actif()
	queue_redraw()

func _draw() -> void:
	var cadre := Rect2(Vector2.ZERO, size)
	if _blessure > 0.0:
		draw_texture_rect(_vignette, cadre, false, Color(Couleurs.PAL.danger.darkened(0.2), _blessure * BLESSURE_ALPHA))
	if _voile > 0.0:
		draw_rect(cadre, Color(_teinte, _voile * VOILE_ALPHA))
