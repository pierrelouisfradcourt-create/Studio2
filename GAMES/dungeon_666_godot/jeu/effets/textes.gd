extends Node2D
## Textes flottants : chiffres de dégâts (qui s'additionnent sur une même cible), soins, or,
## « ESQUIVE », « INVULNÉRABLE », Âmes. Portage de addText / addDamageText / drawTexts de
## GAMES/dungeon_666/src/render/fx.mjs. Un texte naît sur un événement (jamais à chaque image).

const ThemeJeu = preload("res://jeu/theme/theme.gd")

const PLAFOND := 48
const FUSION := 0.3 # s : un coup sur la même cible dans cet intervalle s'ajoute au chiffre
const ELAN := 0.12 # s : le texte naît grossi de moitié puis se pose
const MONTEE := -70.0 # u/s
const LARGEUR := 240.0 # u : boîte de centrage
const CONTOUR := Color(0.04, 0.016, 0.03, 0.85)
const CONTOUR_TAILLE := 4

var _textes: Array[Dictionary] = []
var _police: SystemFont
var _vide := true

func _ready() -> void:
	_police = ThemeJeu.police_corps()
	_police.font_weight = 800

func nombre() -> int:
	return _textes.size()

## Ajoute un texte centré en (x, y) ; rend sa fiche (pour y poser une cible et un montant).
func ajouter(x: float, y: float, texte: String, couleur: Color, taille: int = 15, vie: float = 0.7) -> Dictionary:
	if _textes.size() >= PLAFOND:
		_textes.pop_front()
	var t := {"x": x + (randf() - 0.5) * 10.0, "y": y, "vy": MONTEE, "texte": texte, "couleur": couleur, "taille": taille, "vie": vie, "max": vie, "cible": -1.0, "montant": 0.0}
	_textes.append(t)
	return t

## Chiffre de dégâts : s'additionne au chiffre récent de la même cible, et le relance.
func ajouter_degats(cible: float, x: float, y: float, montant: float, couleur: Color, taille: int, vie: float) -> void:
	for t in _textes:
		if t.cible == cible and t.max - t.vie < FUSION and t.couleur == couleur:
			t.montant += montant
			t.texte = D6Js.num_str(t.montant)
			t.taille = maxi(t.taille, taille)
			t.vie = t.max
			return
	var neuf := ajouter(x, y, D6Js.num_str(montant), couleur, taille, vie)
	neuf.cible = cible
	neuf.montant = montant

## Vrai si ce texte est déjà affiché et encore bien visible (évite d'empiler « INVULNÉRABLE »).
func affiche(texte: String, vie_min: float) -> bool:
	for t in _textes:
		if t.texte == texte and t.vie > vie_min:
			return true
	return false

func vider() -> void:
	_textes.clear()
	queue_redraw()

func avancer(dt: float) -> void:
	var frein := exp(-3.0 * dt)
	var i := _textes.size() - 1
	while i >= 0:
		var t := _textes[i]
		t.vie -= dt
		t.y += t.vy * dt
		t.vy *= frein
		if t.vie <= 0.0:
			_textes.remove_at(i)
		i -= 1
	if not _textes.is_empty() or not _vide:
		queue_redraw()
	_vide = _textes.is_empty()

func _draw() -> void:
	for t in _textes:
		var a := minf(1.0, t.vie / (t.max * 0.5))
		var elan := 1.0 + maxf(0.0, (t.vie - t.max + ELAN) / ELAN) * 0.5
		var taille: int = t.taille
		var c: Color = t.couleur
		c.a = a
		draw_set_transform(Vector2(t.x, t.y), 0.0, Vector2(elan, elan))
		var origine := Vector2(-LARGEUR * 0.5, taille * 0.36)
		draw_string_outline(_police, origine, t.texte, HORIZONTAL_ALIGNMENT_CENTER, LARGEUR, taille, CONTOUR_TAILLE, Color(CONTOUR, CONTOUR.a * a))
		draw_string(_police, origine, t.texte, HORIZONTAL_ALIGNMENT_CENTER, LARGEUR, taille, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
