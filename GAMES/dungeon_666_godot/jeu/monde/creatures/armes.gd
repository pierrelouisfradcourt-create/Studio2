extends RefCounted
## L'ARME du héros, une fonction par type (game.kit.weaponType) : on lit son kit à ce qu'il tient.
## Une arme de mêlée suit le balayage RÉEL du coup (elle s'arme pendant `startup`, traverse
## l'ouverture du coup pendant `active`, reste au bout pendant `recovery`) ; une arme à distance
## reste dans l'axe de visée, corde tendue pendant la préparation.
## Repère d'une arme : origine au centre du héros, x = le long de l'arme.

const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL
const NUIT := Color("#0d2a36")
const ACIER := Color("#e6f7ff")
const FER := Color("#7a8c96")

var p: Pinceau

func _init(pinceau: Pinceau) -> void:
	p = pinceau

func dessiner(g: Dictionary, h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	var kit = g.get("kit")
	var type = kit.get("weaponType") if kit is Dictionary else "lame"
	match type:
		"dagues": _dagues(h, pr, m, main)
		"hache": _hache(h, pr, m, main)
		"marteau": _marteau(h, pr, m, main)
		"arc": _arc(h, pr, m, main)
		"arbalete": _arbalete(h, pr, m, main)
		_: _lame(h, pr, m, main)

static func _coup(h: Dictionary):
	var at = h.get("attack")
	return at if h.state == "attack" and at is Dictionary else null

## Sens du balayage du coup en cours (+1 : sens horaire à l'écran), +1 au repos.
static func _sens(h: Dictionary) -> float:
	var at = _coup(h)
	return -1.0 if at != null and int(at.index) % 2 == 1 else 1.0

## Angle d'une arme qui balaie : au repos sur le côté, puis le long de l'ouverture du coup.
static func _angle_taille(h: Dictionary, repos: float) -> float:
	var at = _coup(h)
	if at == null:
		return h.facing + repos
	var ouverture: float = deg_to_rad(at.def.arc)
	var sens := _sens(h)
	var a0: float = at.angle - ouverture * 0.5 * sens
	match at.phase:
		"startup":
			return lerp_angle(h.facing + repos, a0, smoothstep(0.0, 1.0, at.t / maxf(1e-3, at.dur.startup)))
		"active":
			return a0 + ouverture * sens * clampf(at.t / maxf(1e-3, at.dur.active), 0.0, 1.0)
	return a0 + ouverture * sens

static func _angle_visee(h: Dictionary) -> float:
	var at = _coup(h)
	return h.facing if at == null else at.angle

## Tension de la corde pendant la préparation d'un tir (0..1).
static func _tension(h: Dictionary) -> float:
	var at = _coup(h)
	if at == null or at.phase != "startup":
		return 0.0
	return clampf(at.t / maxf(1e-3, at.dur.startup), 0.0, 1.0)

func _poser(m: Transform2D, angle: float, pr: float, main: Color, prise: float = 0.85) -> void:
	p.poser(m * Transform2D(angle, Vector2.ZERO))
	p.disque(Vector2(prise * pr, 0.0), pr * 0.2, main, NUIT, 1.5)

func _lame(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	_poser(m, _angle_taille(h, 0.9), pr, main)
	_epee(pr, 1.0, 2.45)

## Une lame droite : garde, tranchant effilé, gouttière.
func _epee(pr: float, debut: float, bout: float) -> void:
	p.baton(Vector2((debut - 0.3) * pr, 0.0), Vector2(debut * pr, 0.0), FER, 2.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(debut * pr, -0.15 * pr), Vector2((bout - 0.35) * pr, -0.12 * pr), Vector2(bout * pr, 0.0),
		Vector2((bout - 0.35) * pr, 0.12 * pr), Vector2(debut * pr, 0.15 * pr)]), ACIER, NUIT, 1.5)
	p.ligne(Vector2((debut + 0.1) * pr, 0.0), Vector2((bout - 0.45) * pr, 0.0), PAL.heroCape, 1.2)
	p.baton(Vector2(debut * pr, -0.36 * pr), Vector2(debut * pr, 0.36 * pr), PAL.slashStrike, 2.5, NUIT)

func _dagues(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	_poser(m, h.facing - 0.9, pr, main)
	_epee(pr, 1.0, 1.8)
	_poser(m, _angle_taille(h, 0.7), pr, main)
	_epee(pr, 1.0, 1.8)

func _hache(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	_poser(m, _angle_taille(h, 0.9), pr, main)
	var s := _sens(h)
	p.baton(Vector2(0.55 * pr, 0.0), Vector2(2.45 * pr, 0.0), FER, 3.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(1.6, 0.08 * s) * pr, Vector2(1.55, 0.7 * s) * pr, Vector2(1.95, 1.05 * s) * pr,
		Vector2(2.5, 0.98 * s) * pr, Vector2(2.72, 0.55 * s) * pr, Vector2(2.4, 0.08 * s) * pr]), ACIER, NUIT, 1.5)
	p.filet(PackedVector2Array([Vector2(1.7, 0.72 * s) * pr, Vector2(2.0, 0.9 * s) * pr, Vector2(2.45, 0.84 * s) * pr]), PAL.heroCape, 1.5)
	p.pic(Vector2(1.75, -0.08 * s) * pr, Vector2(2.3, -0.08 * s) * pr, Vector2(2.02, -0.42 * s) * pr, FER, NUIT, 1.5)

func _marteau(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	_poser(m, _angle_taille(h, 0.9), pr, main)
	p.baton(Vector2(0.55 * pr, 0.0), Vector2(2.2 * pr, 0.0), FER, 3.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(1.95, -0.62) * pr, Vector2(2.7, -0.62) * pr, Vector2(2.78, -0.5) * pr, Vector2(2.78, 0.5) * pr,
		Vector2(2.7, 0.62) * pr, Vector2(1.95, 0.62) * pr]), ACIER, NUIT, 1.5)
	for y: float in [-0.36, 0.36]:
		p.ligne(Vector2(1.98, y) * pr, Vector2(2.75, y) * pr, PAL.heroCape, 1.5)

func _arc(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	var tension := _tension(h)
	_poser(m, _angle_visee(h), pr, main, 1.55)
	var bois := Pinceau.pts_arc(Vector2(0.5 * pr, 0.0), pr * 1.15, -1.05, 1.05, 12)
	var encoche := Vector2(bois[0].x - tension * pr * 0.7, 0.0)
	p.filet(PackedVector2Array([bois[0], encoche, bois[12]]), PAL.slash, 1.2)
	p.ruban(bois, ACIER, 3.0, NUIT)
	if tension > 0.0:
		_trait_encoche(encoche, pr * 1.5, pr)

func _arbalete(h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	var tension := _tension(h)
	_poser(m, _angle_visee(h), pr, main, 0.8)
	p.forme(PackedVector2Array([Vector2(0.4, -0.16) * pr, Vector2(2.0, -0.12) * pr, Vector2(2.0, 0.12) * pr, Vector2(0.4, 0.16) * pr]), FER, NUIT, 1.5)
	var branches := Pinceau.pts_arc(Vector2(2.75 * pr, 0.0), pr * 1.0, PI - 0.95, PI + 0.95, 10)
	var noix := Vector2((1.75 - 0.75 * tension) * pr, 0.0)
	p.filet(PackedVector2Array([branches[0], noix, branches[10]]), PAL.slash, 1.2)
	p.ruban(branches, ACIER, 3.0, NUIT)
	if tension > 0.0:
		_trait_encoche(noix, pr * 1.3, pr)

## Le trait prêt à partir (flèche, carreau) : couleur de la Lance, froide.
func _trait_encoche(depart: Vector2, longueur: float, pr: float) -> void:
	var pointe := depart + Vector2(longueur, 0.0)
	p.ligne(depart, pointe, PAL.lance, 2.0)
	p.pic(pointe + Vector2(-0.05, -0.2) * pr, pointe + Vector2(-0.05, 0.2) * pr, pointe + Vector2(0.4, 0.0) * pr, PAL.lance, NUIT, 1.2)
