extends Node2D
## Réservoir de particules : tableaux compacts de taille fixe, aucune allocation après _ready.
## Portage du pool de GAMES/dungeon_666/src/render/fx.mjs (spawnParticle, burst, updateFx,
## drawParticles). Une particule est un carré, ou un trait le long de sa vitesse (`en_trait`).
## Présentation pure : randf() est permis ici, rien ne revient vers la simulation.

## Plafond dur. La version web en a 700 ; 480 suffit (mesuré : un Gardien tué en pleine mêlée
## reste dessous) et tient le budget d'un téléphone.
const PLAFOND := 480
const TRAINE := 0.03 # s : longueur d'un trait = vitesse × TRAINE

## 0,4 à 1 : part du plafond utilisable (pour un réglage de qualité adaptatif).
var qualite := 1.0
## Nombre de particules vivantes.
var n := 0

var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _vie := PackedFloat32Array()
var _max := PackedFloat32Array()
var _taille := PackedFloat32Array()
var _frein := PackedFloat32Array()
var _trait := PackedByteArray()
var _couleur := PackedColorArray()
var _vide := true

func _init() -> void:
	_x.resize(PLAFOND)
	_y.resize(PLAFOND)
	_vx.resize(PLAFOND)
	_vy.resize(PLAFOND)
	_vie.resize(PLAFOND)
	_max.resize(PLAFOND)
	_taille.resize(PLAFOND)
	_frein.resize(PLAFOND)
	_trait.resize(PLAFOND)
	_couleur.resize(PLAFOND)

func emettre(x: float, y: float, vx: float, vy: float, vie: float, taille: float, couleur: Color, frein: float = 4.0, en_trait: bool = false) -> void:
	if n >= int(PLAFOND * qualite):
		return
	_x[n] = x
	_y[n] = y
	_vx[n] = vx
	_vy[n] = vy
	_vie[n] = vie
	_max[n] = vie
	_taille[n] = taille
	_frein[n] = frein
	_trait[n] = 1 if en_trait else 0
	_couleur[n] = couleur
	n += 1

## Gerbe de `nombre` particules depuis (x, y), dans un cône d'`ouverture` radians autour de `dir`.
## `depart` : elles naissent à cette distance du centre (au bord du héros, pour ne pas le couvrir).
func gerbe(x: float, y: float, nombre: int, vitesse: float, vie: float, taille: float, couleur: Color, dir: float = 0.0, ouverture: float = TAU, frein: float = 5.0, en_trait: bool = false, depart: float = 0.0) -> void:
	for k in nombre:
		var a := dir + (randf() - 0.5) * ouverture
		var s := vitesse * (0.35 + randf() * 0.65)
		var c := cos(a)
		var d := sin(a)
		emettre(x + c * depart, y + d * depart, c * s, d * s, vie * (0.6 + randf() * 0.4), taille * (0.6 + randf() * 0.6), couleur, frein, en_trait)

func vider() -> void:
	n = 0
	queue_redraw()

## Fait vieillir et avancer les particules ; les mortes sont écrasées par compactage en place.
func avancer(dt: float) -> void:
	var w := 0
	for i in n:
		var vie := _vie[i] - dt
		if vie <= 0.0:
			continue
		var k := exp(-_frein[i] * dt)
		var vx := _vx[i] * k
		var vy := _vy[i] * k
		_x[w] = _x[i] + vx * dt
		_y[w] = _y[i] + vy * dt
		_vx[w] = vx
		_vy[w] = vy
		_vie[w] = vie
		if w != i:
			_max[w] = _max[i]
			_taille[w] = _taille[i]
			_frein[w] = _frein[i]
			_trait[w] = _trait[i]
			_couleur[w] = _couleur[i]
		w += 1
	n = w
	if n > 0 or not _vide:
		queue_redraw()
	_vide = n == 0

## Deux passes (les carrés, puis les traits) : le moteur regroupe alors chaque passe en très peu
## d'appels de dessin, au lieu d'en changer à chaque alternance carré / trait.
func _draw() -> void:
	var traits := 0
	for i in n:
		if _trait[i] == 1:
			traits += 1
			continue
		var c := _couleur[i]
		c.a *= _vie[i] / _max[i]
		var s := _taille[i]
		draw_rect(Rect2(_x[i] - s * 0.5, _y[i] - s * 0.5, s, s), c)
	if traits > 0:
		for i in n:
			if _trait[i] == 0:
				continue
			var c := _couleur[i]
			c.a *= _vie[i] / _max[i]
			draw_line(Vector2(_x[i], _y[i]), Vector2(_x[i] - _vx[i] * TRAINE, _y[i] - _vy[i] * TRAINE), c, _taille[i])
