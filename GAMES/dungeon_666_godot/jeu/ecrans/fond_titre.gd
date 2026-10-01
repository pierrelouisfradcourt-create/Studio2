extends Control
## Le fond de l'écran titre, entièrement DESSINÉ (aucune image) : la lueur de braise qui monte du
## bas et qui respire, la silhouette de Dité sur deux plans, des braises qui montent, un halo
## derrière le logo, une vignette. Sobre : rien ne bouge vite, rien ne passe devant les boutons
## avec assez de lumière pour gêner la lecture. Présentation pure, tirages de décor seulement.

const Couleurs = preload("res://jeu/theme/couleurs.gd")

const GRAINE := 666
const BRAISES := 46
const SOUFFLE := 0.8 # rad/s : la lueur respire en ~8 s
const LUEUR := 0.3 # opacité moyenne de la lueur du bas
const LUEUR_SOUFFLE := 0.09 # son battement
const HALO_LOGO := 0.1
const TOURS_LOIN := 22
const TOURS_PRES := 13
const FLECHE_MAX := 0.055 # hauteur maximale d'une flèche (part de l'écran)
const FENETRES := 0.3 # part des tours proches qui ont une fenêtre allumée
const MONTEE := Vector2(0.018, 0.05) # part de la hauteur montée par seconde (mini, maxi)

var _temps := 0.0
var _fond: GradientTexture2D
var _halo: GradientTexture2D
var _vignette: GradientTexture2D
var _braises: Array[Dictionary] = []
var _loin: Array[Dictionary] = []
var _pres: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui: Dictionary = Couleurs.UI
	_fond = _radial([ui.ember.darkened(0.68), ui["void"]], [0.0, 1.0], Vector2(0.5, 1.2), Vector2(0.5, 0.1))
	_halo = _radial([Color.WHITE, Color(1, 1, 1, 0)], [0.0, 1.0], Vector2(0.5, 0.5), Vector2(1.0, 0.5))
	_vignette = _radial([Color(ui["void"], 0.0), Color(ui["void"], 0.0), Color(ui["void"], 0.85)], [0.0, 0.55, 1.0], Vector2(0.5, 0.5), Vector2(1.15, 0.5))
	var alea := RandomNumberGenerator.new()
	alea.seed = GRAINE
	for i in BRAISES:
		_braises.append({
			"x": alea.randf(), "phase": alea.randf(), "vitesse": alea.randf_range(MONTEE.x, MONTEE.y),
			"taille": alea.randf_range(1.0, 2.6), "derive": alea.randf_range(0.3, 1.1), "teinte": alea.randf(),
		})
	_loin = _tours(alea, TOURS_LOIN, 0.05, 0.12)
	_pres = _tours(alea, TOURS_PRES, 0.02, 0.07)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_temps += delta
		queue_redraw()

static func _radial(couleurs: Array, reperes: Array, de: Vector2, vers: Vector2) -> GradientTexture2D:
	var degrade := Gradient.new()
	degrade.offsets = PackedFloat32Array(reperes)
	degrade.colors = PackedColorArray(couleurs)
	var texture := GradientTexture2D.new()
	texture.gradient = degrade
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = de
	texture.fill_to = vers
	texture.width = 128
	texture.height = 128
	return texture

## Une rangée de tours : {x, l, h (parts de l'écran), fleche: bool, fenetre: float (0 = aucune)}.
static func _tours(alea: RandomNumberGenerator, nombre: int, h_min: float, h_max: float) -> Array[Dictionary]:
	var tours: Array[Dictionary] = []
	for i in nombre:
		tours.append({
			"x": (i + alea.randf_range(-0.3, 0.3)) / nombre, "l": alea.randf_range(0.6, 1.5) / nombre,
			"h": alea.randf_range(h_min, h_max), "fleche": alea.randf() < 0.4,
			"fenetre": alea.randf_range(0.3, 0.8) if alea.randf() < FENETRES else 0.0,
		})
	return tours

func _draw() -> void:
	var ui: Dictionary = Couleurs.UI
	var cadre := Rect2(Vector2.ZERO, size)
	var souffle := sin(_temps * SOUFFLE)
	draw_texture_rect(_fond, cadre, false)
	_lueur(Vector2(0.5, 1.02), Vector2(1.5, 1.0), Color(ui.ember, LUEUR + LUEUR_SOUFFLE * souffle))
	_lueur(Vector2(0.5, 0.33), Vector2(0.95, 0.55), Color(ui.ember, HALO_LOGO * (1.0 + 0.3 * souffle)))
	_cite(_loin, ui["void"].lerp(ui.ember.darkened(0.72), 0.55), 0.0)
	_cite(_pres, ui["void"].lerp(ui.ember.darkened(0.9), 0.4), 0.14 + 0.05 * souffle)
	_dessiner_braises()
	draw_texture_rect(_vignette, cadre, false)

## Halo doux centré en `centre` (parts de l'écran), d'étendue `etendue` (parts de l'écran).
func _lueur(centre: Vector2, etendue: Vector2, couleur: Color) -> void:
	var taille := etendue * size
	draw_texture_rect(_halo, Rect2(centre * size - taille / 2.0, taille), false, couleur)

## La cité en ombre chinoise : des tours, certaines coiffées d'une flèche, quelques fenêtres.
func _cite(tours: Array[Dictionary], couleur: Color, fenetres: float) -> void:
	var braise: Color = Couleurs.UI.ember
	for t in tours:
		var l: float = t.l * size.x
		var h: float = t.h * size.y
		var x: float = t.x * size.x
		draw_rect(Rect2(x, size.y - h, l, h), couleur)
		if t.fleche:
			var pointe := minf(l * 1.4, size.y * FLECHE_MAX)
			draw_colored_polygon(PackedVector2Array([Vector2(x + l * 0.28, size.y - h), Vector2(x + l / 2.0, size.y - h - pointe), Vector2(x + l * 0.72, size.y - h)]), couleur)
		if fenetres > 0.0 and t.fenetre > 0.0:
			draw_rect(Rect2(x + l * 0.42, size.y - h * t.fenetre, maxf(2.0, l * 0.12), maxf(3.0, l * 0.22)), Color(braise, fenetres))

func _dessiner_braises() -> void:
	var pal: Dictionary = Couleurs.PAL
	for b in _braises:
		var u := fposmod(b.phase + _temps * b.vitesse, 1.0)
		var p := Vector2(b.x * size.x + sin(_temps * b.derive + b.phase * 20.0) * 16.0, size.y * (1.04 - u * 1.1))
		# Naît au bas, s'éteint en montant ; un léger scintillement.
		var a := sin(u * PI) * (0.65 + 0.35 * sin(_temps * 5.0 + b.phase * 40.0)) * (1.0 - u * 0.5)
		var c: Color = (pal.lava as Color).lerp(pal.gold, b.teinte * 0.6)
		draw_circle(p, b.taille * 3.2, Color(c, a * 0.12), true, -1.0, true)
		draw_circle(p, b.taille, Color(c, a * 0.9), true, -1.0, true)
