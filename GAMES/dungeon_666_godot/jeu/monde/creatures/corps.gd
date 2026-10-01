extends Node2D
## Le CORPS d'un ennemi : un nœud par créature. Son dessin (confié à ennemis.gd) est GARDÉ d'une
## image à l'autre et refait seulement quand sa pose change, ou vingt fois par seconde pour ce
## qui bouge DANS le corps (ailes, flammes, étendard). Tout le reste de la vie de la créature
## passe par le REPÈRE du nœud, recalculé à chaque image, ce qui ne coûte presque rien :
##   respiration       le corps enfle et désenfle (horloge du dessin)
##   marche            balancement lié à la distance RÉELLEMENT parcourue
##   anticipation      il se ramasse en arrière pendant son télégraphe (e.tele.progress)
##   détente           il s'étire en avant à l'instant où le coup part
##   impact            écrasé puis étiré dans l'axe du coup reçu (e.flash, e.hitDirX/Y)
##   étourdissement    il vacille
## Repère du dessin : origine au centre, x = devant lui. Le nœud ne modifie jamais la partie.

const CADENCE := 0.05 # s entre deux dessins d'un corps dont la pose ne change pas
const APPARITION := 0.25 # s : durée de l'apparition (spawnT de la simulation)
const REBOND := 1.70158 # dépassement de l'apparition (0 -> 1,15 -> 1)
const TREMBLE := 2.0 # u : tremblement le long du coup pendant le gel d'impact
const DETENTE := 0.22 # s : étirement à la frappe
const CHOC := 0.45 # s : écrasement puis rebond après un coup reçu
const PIVOT := 16.0 # 1/s : vitesse à laquelle le regard rattrape le héros
const SAUT := 150.0 # u : au-delà, c'est une téléportation, pas un pas

var calque: Node2D
var e: Dictionary
## Lus par les dessins (archetypes.gd, nouveaux.gd, gardiens.gd).
var face := 0.0
var allure := 0.0 # 0 immobile .. 1 à sa vitesse de marche
var marche := 0.0 # phase du pas (rad), avance avec la distance parcourue
var anticipation := 0.0 # 0..1 : part du télégraphe écoulée

var _cle := ""
var _prochain := 0.0
var _avant := Vector2.INF
var _flash := 0.0
var _choc := 9.0
var _choc_axe := 0.0
var _detente := 9.0
var _neuf := true

func _draw() -> void:
	calque.peindre(self)

## Une image : le corps suit son ennemi. `cible` = position dessinée du héros.
func suivre(p_e: Dictionary, g: Dictionary, cible: Vector2, delta: float) -> void:
	e = p_e
	var boss: bool = D6Js.truthy(e.boss)
	visible = boss or not D6Js.truthy(e.get("hidden"))
	if not visible:
		_avant = Vector2.INF
		_neuf = true
		return
	var pos: Vector2 = calque.lieu(e)
	var t: float = calque.temps()
	_pas(pos, delta, g)
	_chocs(g, delta)
	_regarder(pos, cible, delta)
	transform = _ecrase(g, _repere(g, pos, t, boss))
	modulate.a = _alpha(g, t)
	_neuf = false
	var cle := str(e.state, e.flash > 0.0, e.stun > 0.0)
	if boss or cle != _cle or t >= _prochain or _presse():
		_cle = cle
		_prochain = t + CADENCE
		queue_redraw()

## Le Traqueur qui se dissout ou resurgit fume : sa fumée se redessine à chaque image.
func _presse() -> bool:
	return e.kind == "stalker" and (e.state == "fade" or e.state == "windup")

## Distance parcourue depuis la dernière image : elle fait avancer le pas et donne l'allure.
func _pas(pos: Vector2, delta: float, g: Dictionary) -> void:
	var d := 0.0 if _avant == Vector2.INF else pos.distance_to(_avant)
	_avant = pos
	if d > SAUT:
		d = 0.0
	var def = g.tuning.enemies.get(e.kind)
	var ref: float = def.speed if def != null and def.has("speed") else 110.0
	var vise := 0.0 if e.stun > 0.0 or e.flash > 0.0 else clampf(d / maxf(1e-4, delta) / maxf(40.0, ref * 0.8), 0.0, 1.0)
	allure = lerpf(allure, vise, 1.0 - exp(-10.0 * delta))
	marche += d * PI / (e.r * 1.5)

## Coup reçu (e.flash remonte) et détente (le télégraphe vient de s'achever).
func _chocs(g: Dictionary, delta: float) -> void:
	if e.flash > _flash + 1e-4:
		var coup := Vector2(calque.nombre(e, "hitDirX"), calque.nombre(e, "hitDirY"))
		if coup != Vector2.ZERO:
			_choc = 0.0
			_choc_axe = coup.angle()
	elif g.hitstop <= 0.0 and e.freeze <= 0.0:
		_choc += delta
	_flash = e.flash
	var k := _telegraphe(g)
	if anticipation > 0.6 and k <= 0.0 and e.stun <= 0.0:
		_detente = 0.0
	else:
		_detente += delta
	anticipation = k

## Part du télégraphe écoulée : l'alerte de la simulation, sinon la durée de l'état `windup`.
func _telegraphe(g: Dictionary) -> float:
	if e.stun > 0.0:
		return 0.0
	var tele = e.get("tele")
	if tele is Dictionary and not D6Js.truthy(tele.get("harmless")):
		return clampf(calque.nombre(tele, "progress"), 0.0, 1.0)
	if e.state != "windup" or D6Js.truthy(e.boss):
		return 0.0
	var def: Dictionary = g.tuning.enemies[e.kind]
	var duree: float = D6Js.nz(def.get("slashWindup"), D6Js.nz(def.get("windup"), 0.5))
	return clampf(e.stateTime / maxf(1e-3, duree), 0.0, 1.0)

## Il regarde le héros, en tournant vite mais pas d'un bloc. Le Porte-pavois regarde où est son
## pavois (e.face : c'est la règle), le bélier et le diablotin lancés regardent où ils foncent.
func _regarder(pos: Vector2, cible: Vector2, delta: float) -> void:
	var vise := (cible - pos).angle()
	var pose = e.get("face")
	if pose is float:
		face = pose
		return
	if (e.kind == "charger" and e.state == "charge") or (e.kind == "imp" and e.state == "strike"):
		vise = Vector2(e.dirX, e.dirY).angle()
	face = vise if _neuf else lerp_angle(face, vise, 1.0 - exp(-PIVOT * delta))

## Repère du corps : respiration, balancement du pas, anticipation, détente, vacillement.
func _repere(g: Dictionary, pos: Vector2, t: float, boss: bool) -> Transform2D:
	var haut: float = calque.envol(e)
	var souffle := sin(t * (1.7 if boss else 2.6) + e.id * 1.3) * (2.2 if e.state == "recover" else 1.0)
	var ech := Vector2(1.0 + 0.012 * souffle, 1.0 + 0.028 * souffle)
	var angle := face + sin(marche) * 0.12 * allure
	var avance := 0.0
	var k := anticipation * anticipation * (3.0 - 2.0 * anticipation) * (0.5 if boss else 1.0)
	if e.kind != "exploder":
		ech *= Vector2(1.0 - 0.18 * k, 1.0 + 0.13 * k)
		avance -= 0.24 * e.r * k
	if _detente < DETENTE:
		var d := 1.0 - _detente / DETENTE
		d *= d * (0.5 if boss else 1.0)
		ech *= Vector2(1.0 + 0.3 * d, 1.0 - 0.17 * d)
		avance += 0.32 * e.r * d
	var o := pos - Vector2(0.0, haut * e.r * 1.3)
	if e.stun > 0.0 and not boss:
		angle += sin(t * 6.5 + e.id) * 0.26
		o += Vector2(cos(t * 5.0 + e.id), sin(t * 5.0 + e.id) * 0.5) * 1.6
	var dir := Vector2.from_angle(face)
	o += dir * avance + dir.orthogonal() * (sin(marche) * 0.07 * e.r * allure)
	return Transform2D(angle, ech * (_echelle(g) * (1.0 + 0.18 * haut)), 0.0, o)

## Écrasé puis étiré dans l'axe du coup reçu (aire conservée) ; il tremble pendant le gel d'impact.
func _ecrase(g: Dictionary, m: Transform2D) -> Transform2D:
	if _choc >= CHOC:
		return m
	var o := m.origin
	if e.flash > 0.0 and (g.hitstop > 0.0 or e.freeze > 0.0):
		o += Vector2.from_angle(_choc_axe) * (TREMBLE if int(calque.temps() * 60.0) % 2 == 0 else -TREMBLE)
	if D6Js.truthy(e.boss):
		m.origin = o
		return m
	var f := 1.0 - 0.3 * exp(-_choc * 9.0) * cos(_choc * 24.0)
	m.origin = Vector2.ZERO
	m = Transform2D(_choc_axe, Vector2(f, 1.0 / f), 0.0, Vector2.ZERO) * Transform2D(-_choc_axe, Vector2.ZERO) * m
	m.origin = o
	return m

## Taille dessinée : rebond d'apparition, possédé qui gonfle avant d'exploser.
func _echelle(g: Dictionary) -> float:
	var s := 1.0
	if e.spawnT > 0.0 and not D6Js.truthy(e.get("hidden")):
		var k: float = 1.0 - clampf(e.spawnT / APPARITION, 0.0, 1.0)
		s = maxf(0.05, 1.0 + (REBOND + 1.0) * pow(k - 1.0, 3.0) + REBOND * pow(k - 1.0, 2.0))
	if e.kind == "exploder" and e.state == "windup":
		var duree: float = maxf(1e-3, g.tuning.enemies.exploder.windup)
		s *= 1.0 + 0.45 * clampf(e.stateTime / duree, 0.0, 1.0) + 0.04 * sin(e.stateTime * 40.0)
	return s

## Opacité : apparition, Minos dissous (en filigrane). Le Traqueur qui se dissout règle la
## sienne dans son dessin (nouveaux.gd) : sa fumée, elle, reste visible.
func _alpha(_g: Dictionary, t: float) -> float:
	if D6Js.truthy(e.get("hidden")):
		return 0.28 + 0.12 * sin(t * 20.0)
	if e.spawnT > 0.0:
		return 0.5 + 0.5 * (1.0 - clampf(e.spawnT / APPARITION, 0.0, 1.0))
	return 1.0
