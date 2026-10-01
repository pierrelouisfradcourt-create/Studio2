extends "res://jeu/monde/creatures/calque.gd"
## Calque des ENNEMIS et des GARDIENS : chaque corps est posé dans un repère tourné vers le héros
## (x = devant lui), grossi à l'apparition, écrasé dans l'axe du coup reçu, puis confié au
## dessin de son archétype (archetypes.gd) ou de son modèle de Gardien (gardiens.gd).

const Archetypes = preload("res://jeu/monde/creatures/archetypes.gd")
const Gardiens = preload("res://jeu/monde/creatures/gardiens.gd")

const APPARITION := 0.25 # s : durée de l'apparition (spawnT de la simulation)
const REBOND := 1.70158 # dépassement de l'apparition (0 -> 1,15 -> 1)
const ECRASE := Vector2(0.8, 1.25) # touché : écrasé dans l'axe du coup, aire conservée
const TREMBLE := 2.0 # u : tremblement le long du coup pendant le gel d'impact

var _corps := {}
var _bestiaire: Archetypes
var _gardiens: Gardiens

func _init() -> void:
	super()
	_bestiaire = Archetypes.new(p)
	_gardiens = Gardiens.new(p)
	_corps = {
		"imp": PAL.imp, "archer": PAL.archer, "brute": PAL.brute, "charger": PAL.charger, "exploder": PAL.exploder,
		"pyromancer": Color("#a8233a"), "necromancer": Color("#5a3690"),
		"gardien": PAL.boss, "cerbere": Color("#8a2e1e"), "minos": Color("#3a2e6e"), "colosse": Color("#6b5a50"),
	}

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	_bestiaire.temps = temps()
	_gardiens.temps = temps()
	var cible := lieu_heros(g)
	var liste := vivants(g)
	liste.sort_custom(func(a, b): return a.y < b.y)
	for e in liste:
		_dessiner(e, g, cible)
	p.alpha = 1.0
	p.lever()

func _dessiner(e: Dictionary, g: Dictionary, cible: Vector2) -> void:
	var pos := lieu(e)
	var face := _face(e, pos, cible)
	var haut := envol(e)
	var r: float = e.r * _echelle(e, g) * (1.0 + 0.18 * haut)
	p.alpha = _alpha(e)
	if D6Js.truthy(e.eliteMod):
		p.poser(Transform2D(0.0, pos))
		p.pointille(Vector2.ZERO, r + 7.0, Couleurs.ELITE_COLORS[e.eliteMod], 3.0, 14.0, -temps() * 30.0 / (r + 7.0))
	var m := _repere(e, g, pos - Vector2(0.0, haut * e.r * 1.3))
	p.poser(m * Transform2D(face, Vector2.ZERO))
	var corps: Color = PAL.enemyFlash if e.flash > 0.0 else _corps.get(e.kind, PAL.imp)
	if D6Js.truthy(e.boss):
		_gardiens.dessiner(e, r, face, corps)
	else:
		_bestiaire.dessiner(e, r, face, corps, g)

## Il regarde le héros ; le bélier lancé regarde où il court.
func _face(e: Dictionary, pos: Vector2, cible: Vector2) -> float:
	if e.kind == "charger" and e.state == "charge":
		return Vector2(e.dirX, e.dirY).angle()
	return (cible - pos).angle()

func _alpha(e: Dictionary) -> float:
	if D6Js.truthy(e.get("hidden")):
		return 0.28 + 0.12 * sin(temps() * 20.0) # Minos dissous : en filigrane
	if e.spawnT > 0.0:
		return 0.5 + 0.5 * (1.0 - clampf(e.spawnT / APPARITION, 0.0, 1.0))
	return 1.0

## Taille dessinée : rebond d'apparition, frémissement de l'attaque qui se prépare, possédé qui gonfle.
func _echelle(e: Dictionary, g: Dictionary) -> float:
	var s := 1.0
	if e.spawnT > 0.0:
		var k: float = 1.0 - clampf(e.spawnT / APPARITION, 0.0, 1.0)
		s = maxf(0.05, 1.0 + (REBOND + 1.0) * pow(k - 1.0, 3.0) + REBOND * pow(k - 1.0, 2.0))
	if e.state != "windup":
		return s
	if e.kind == "exploder":
		var duree: float = maxf(1e-3, g.tuning.enemies.exploder.windup)
		return s * (1.0 + 0.45 * clampf(e.stateTime / duree, 0.0, 1.0) + 0.04 * sin(e.stateTime * 40.0))
	return s * (1.0 + 0.08 * sin(e.stateTime * 30.0))

## Repère du corps : tremblement pendant le gel d'impact, puis écrasement dans l'axe du coup.
func _repere(e: Dictionary, g: Dictionary, pos: Vector2) -> Transform2D:
	var m := Transform2D(0.0, pos)
	var coup := Vector2(nombre(e, "hitDirX"), nombre(e, "hitDirY"))
	if e.flash <= 0.0 or coup == Vector2.ZERO:
		return m
	var a := coup.angle()
	if g.hitstop > 0.0 or e.freeze > 0.0:
		m.origin += Vector2.from_angle(a) * (TREMBLE if int(temps() * 60.0) % 2 == 0 else -TREMBLE)
	if D6Js.truthy(e.boss):
		return m
	return m * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, ECRASE, 0.0, Vector2.ZERO) * Transform2D(-a, Vector2.ZERO)
