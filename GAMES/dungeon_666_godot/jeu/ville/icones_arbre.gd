extends RefCounted
## Pictogrammes et FORMES des nœuds de l'arbre de compétences (jeu/ville/arbre.gd), DESSINÉS dans
## un lot de triangles déjà ouvert (jeu/theme/triangles.gd). Les compétences, le déplacement et
## l'ultime gardent le pictogramme de leur bouton en jeu (jeu/interface/icones.gd) ; ici vivent
## ceux des PASSIFS, et les trois formes de médaillon :
##   compétence : rond · passif : losange · déplacement et ultime : écusson.
##   const IconesArbre = preload("res://jeu/ville/icones_arbre.gd")
##   IconesArbre.ajouter(lot, IconesArbre.passif(noeud.text), centre, rayon, couleur)
##
## `tree_view` ne dit pas QUELLE statistique porte un passif (son champ `icon` est vide) : le
## pictogramme est choisi d'après les mots de son texte (MOTS, du plus précis au plus vague), et à
## défaut c'est l'étoile. Ce n'est qu'un habillage : aucun nombre, aucune condition n'en dépend.

const Triangles = preload("res://jeu/theme/triangles.gd")

const NOMS := ["coeur", "oeil", "sablier", "aile", "bouclier", "charge", "lame", "couronne", "poing", "etoile"]
const DEFAUT := "etoile"
## [mot cherché dans le texte du passif (sans égard aux majuscules), pictogramme]
const MOTS := [
	["pv", "coeur"], ["critique", "oeil"], ["ultime", "couronne"], ["armure", "bouclier"], ["recul", "poing"],
	["vitesse", "aile"], ["plus vite", "sablier"], ["dégâts", "lame"], ["recharge", "sablier"], ["charge", "charge"],
]
## Sommets des formes, en fractions du rayon du médaillon.
const LOSANGE := [[0.0, -1.18], [1.18, 0.0], [0.0, 1.18], [-1.18, 0.0]]
const ECUSSON := [[-0.92, -0.98], [0.92, -0.98], [0.92, 0.22], [0.0, 1.16], [-0.92, 0.22]]

static func connue(nom) -> bool:
	return nom is String and nom in NOMS

## Le pictogramme d'un passif, d'après son texte ; l'étoile si aucun mot n'y est.
static func passif(texte: String) -> String:
	var t := texte.to_lower()
	for paire in MOTS:
		if t.contains(paire[0]):
			return paire[1]
	return DEFAUT

## Le contour d'une forme de médaillon autour de l'origine ("skill" : vide, c'est un disque).
static func forme(sorte: String, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if sorte == "skill":
		return pts
	for s in (LOSANGE if sorte == "passive" else ECUSSON):
		pts.append(Vector2(s[0], s[1]) * r)
	return pts

## Ajoute le pictogramme `nom` au lot, centré en `c`, à l'échelle d'un médaillon de rayon `r`.
static func ajouter(lot: Triangles, nom: String, c: Vector2, r: float, col: Color) -> void:
	var avant := lot.repere
	lot.repere = avant * Transform2D(0.0, c)
	match nom:
		"coeur": _coeur(lot, r, col)
		"oeil": _oeil(lot, r, col)
		"sablier": _sablier(lot, r, col)
		"aile": _aile(lot, r, col)
		"bouclier": _bouclier(lot, r, col)
		"charge": _charge(lot, r, col)
		"lame": _lame(lot, r, col)
		"couronne": _couronne(lot, r, col)
		"poing": _poing(lot, r, col)
		_: _etoile(lot, r, col)
	lot.repere = avant

static func _poly(lot: Triangles, r: float, sommets: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for s in sommets:
		pts.append(Vector2(s[0], s[1]) * r)
	lot.polygone(pts, col)

## Vie : un cœur (deux lobes, une pointe).
static func _coeur(lot: Triangles, r: float, col: Color) -> void:
	for x: float in [-0.2, 0.2]:
		lot.disque(Vector2(x, -0.14) * r, r * 0.24, col)
	_poly(lot, r, [[-0.43, -0.04], [0.43, -0.04], [0.0, 0.5]], col)

## Critique : une cible — un anneau, son centre, quatre repères.
static func _oeil(lot: Triangles, r: float, col: Color) -> void:
	lot.arc(Vector2.ZERO, r * 0.36, 0.0, TAU, 20, col, r * 0.1)
	lot.disque(Vector2.ZERO, r * 0.12, col)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		lot.ligne(d * r * 0.44, d * r * 0.62, col, r * 0.1)

## Recharge plus courte : un sablier.
static func _sablier(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[-0.34, -0.48], [0.34, -0.48], [0.0, 0.0]], col)
	_poly(lot, r, [[-0.34, 0.48], [0.34, 0.48], [0.0, 0.0]], col)
	lot.rect(Rect2(-0.4 * r, -0.56 * r, 0.8 * r, 0.1 * r), col)
	lot.rect(Rect2(-0.4 * r, 0.46 * r, 0.8 * r, 0.1 * r), col)

## Vitesse : trois plumes couchées.
static func _aile(lot: Triangles, r: float, col: Color) -> void:
	for i in 3:
		var y := -0.3 + i * 0.3
		_poly(lot, r, [[-0.5 + i * 0.12, y + 0.1], [0.5, y - 0.12], [0.3, y + 0.1]], col)

## Armure : un bouclier plein.
static func _bouclier(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[-0.42, -0.46], [0.42, -0.46], [0.42, 0.08], [0.0, 0.54], [-0.42, 0.08]], col)

## Charge de plus : deux pastilles et un « plus ».
static func _charge(lot: Triangles, r: float, col: Color) -> void:
	for x: float in [-0.36, -0.02]:
		lot.disque(Vector2(x, 0.12) * r, r * 0.15, col)
	lot.rect(Rect2(0.22 * r, 0.07 * r, 0.32 * r, 0.1 * r), col)
	lot.rect(Rect2(0.33 * r, -0.04 * r, 0.1 * r, 0.32 * r), col)

## Dégâts : une lame dressée et sa garde.
static func _lame(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[0.0, -0.6], [0.14, -0.36], [0.14, 0.18], [-0.14, 0.18], [-0.14, -0.36]], col)
	lot.rect(Rect2(-0.32 * r, 0.18 * r, 0.64 * r, 0.1 * r), col)
	lot.rect(Rect2(-0.07 * r, 0.28 * r, 0.14 * r, 0.26 * r), col)

## Ultime plus vite : une couronne à trois pointes.
static func _couronne(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[-0.48, 0.32], [-0.5, -0.3], [-0.24, 0.0], [0.0, -0.44], [0.24, 0.0], [0.5, -0.3], [0.48, 0.32]], col)
	lot.rect(Rect2(-0.48 * r, 0.38 * r, 0.96 * r, 0.1 * r), col)

## Recul : un poing fermé et son élan.
static func _poing(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[-0.1, -0.34], [0.46, -0.34], [0.52, 0.2], [0.34, 0.36], [-0.1, 0.36]], col)
	for y: float in [-0.22, 0.0, 0.22]:
		lot.rect(Rect2(-0.54 * r, (y - 0.04) * r, 0.3 * r, 0.08 * r), col)

## À défaut : une étoile à quatre branches.
static func _etoile(lot: Triangles, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.from_angle(i * TAU / 8.0 - PI / 2.0) * r * (0.56 if i % 2 == 0 else 0.2))
	lot.polygone(pts, col)
