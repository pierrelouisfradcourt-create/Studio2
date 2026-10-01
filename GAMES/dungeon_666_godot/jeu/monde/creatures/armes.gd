extends RefCounted
## L'ARME du héros, une fonction par type (game.kit.weaponType) : on lit son kit à ce qu'il tient.
##   lame      épée droite à garde                dagues    deux lames courtes, une par main
##   hache     long manche, fer en croissant      maillet   tête massive cerclée
##   arc       grand arc, corde et flèche         arbalète  fût, branches courtes, carreau
## Une arme de mêlée suit la phase RÉELLE du coup (p.attack.phase, .t, .dur) :
##   startup   elle S'ARME : ramenée en arrière, au-delà du bord où le coup commence
##   active    elle FRAPPE : elle traverse l'ouverture du coup, bras tendu, vite puis ralentie
##   recovery  elle tient un instant au bout du geste, puis REVIENT à la garde
## Une arme à distance reste dans l'axe de visée : corde tendue pendant la préparation, lâchée
## (recul) au départ du trait. Pendant un Super, l'arme joue le Super (tourbillon, exécution, nuée).
## Repère d'une arme : origine au centre du héros, x = le long de l'arme.

const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL
const NUIT := Color("#0d2a36")
const ACIER := Color("#e6f7ff")
const FER := Color("#7a8c96")
const BRAISE := Color("#ffd98a") # acier chauffé par l'élan
const OR := Color("#ffe9a8") # acier d'un Super
const TENUE := 0.35 # part de la récupération où l'arme reste au bout du geste
const EXECUTION := 0.24 # s : durée du geste d'une exécution (Super du Bourreau)

var p: Pinceau
## Posés par le calque du héros avant chaque dessin.
var temps := 0.0
var pas := 0.0 # balancement de la course, -1..1
var chaud := 0.0 # élan (player.surge) : 0..1
var execution := 9.0 # s écoulées depuis la dernière exécution (Super « sentence »)
var execution_angle := 0.0
var execution_arc := 0.0
var execution_sens := 1.0
var tir := 9.0 # s écoulées depuis le dernier trait de la Nuée
var tir_angle := 0.0

var _acier := ACIER
var _fil: Color = PAL.heroCape

func _init(pinceau: Pinceau) -> void:
	p = pinceau

func dessiner(g: Dictionary, h: Dictionary, pr: float, m: Transform2D, main: Color) -> void:
	var kit = g.get("kit")
	var type = kit.get("weaponType") if kit is Dictionary else "lame"
	var en_super: bool = h.state == "super"
	_acier = OR if en_super else ACIER.lerp(BRAISE, 0.85 * chaud)
	_fil = PAL.superBar if en_super else PAL.heroCape.lerp(PAL.superBar, chaud)
	var genre = g.tuning["super"].get("kind") if en_super else ""
	match type:
		"dagues": _dagues(h, pr, m, main, genre)
		"hache": _hache(h, pr, m, main, genre)
		"marteau": _marteau(h, pr, m, main, genre)
		"arc": _arc(h, pr, m, main, genre)
		"arbalete": _arbalete(h, pr, m, main, genre)
		_: _lame(h, pr, m, main, genre)

static func _coup(h: Dictionary):
	var at = h.get("attack")
	return at if h.state == "attack" and at is Dictionary else null

## Sens du balayage du coup en cours (+1 : sens horaire à l'écran), +1 au repos.
static func _sens(h: Dictionary) -> float:
	var at = _coup(h)
	return -1.0 if at != null and int(at.index) % 2 == 1 else 1.0

## Pose d'une arme de mêlée : x = son angle, y = avance de la main (en rayons), z = sa taille.
## `repos` = l'angle de la garde, compté depuis le regard du héros.
func _pose(h: Dictionary, repos: float, genre) -> Vector3:
	var garde: float = h.facing + repos + pas * 0.2
	if genre != "":
		return _pose_super(h, garde, genre)
	var at = _coup(h)
	if at == null:
		if h.state == "dash":
			return Vector3(Vector2(h.dashDirX, h.dashDirY).angle() + PI - 0.45 * signf(repos), -0.1, 1.0)
		return Vector3(garde, 0.0, 1.0)
	var ouverture: float = deg_to_rad(at.def.arc)
	var sens := _sens(h)
	var arme: float = at.angle - ouverture * 0.5 * sens - 0.5 * sens
	var bout: float = at.angle + ouverture * 0.5 * sens + 0.12 * sens
	match at.phase:
		"startup":
			var k: float = clampf(at.t / maxf(1e-3, at.dur.startup), 0.0, 1.0)
			return Vector3(lerp_angle(garde, arme, 1.0 - (1.0 - k) * (1.0 - k)), -0.18 * k, 1.0 + 0.1 * k)
		"active":
			var k: float = clampf(at.t / maxf(1e-3, at.dur.active), 0.0, 1.0)
			return Vector3(lerpf(arme, bout, 1.0 - (1.0 - k) * (1.0 - k)), 0.38 * sin(PI * minf(1.0, k * 1.15)), 1.22)
	var fin: float = clampf(at.t / maxf(1e-3, at.dur.recovery), 0.0, 1.0)
	if fin < TENUE:
		return Vector3(bout, 0.2 * (1.0 - fin / TENUE), 1.22 - 0.22 * fin / TENUE)
	return Vector3(lerp_angle(bout, garde, smoothstep(TENUE, 1.0, fin)), 0.0, 1.0)

## Pendant un Super : la Colère fait tournoyer l'arme ; la Sentence la lève, dorée, puis l'abat sur
## l'ouverture réelle de chaque exécution ; sinon elle reste en garde.
func _pose_super(h: Dictionary, garde: float, genre) -> Vector3:
	if genre == "colere":
		return Vector3(temps * 22.0 + (PI if garde < h.facing else 0.0), 0.35, 1.25)
	if genre == "sentence":
		if execution < EXECUTION:
			var k := execution / EXECUTION
			var depart := execution_angle - (execution_arc * 0.5 + 0.4) * execution_sens
			return Vector3(depart + (execution_arc + 0.6) * execution_sens * (1.0 - (1.0 - k) * (1.0 - k)), 0.45, 1.5)
		return Vector3(h.facing + 2.5 * execution_sens + 0.06 * sin(temps * 40.0), -0.1, 1.35)
	return Vector3(garde, 0.0, 1.0)

static func _angle_visee(h: Dictionary) -> float:
	var at = _coup(h)
	return h.facing if at == null else at.angle

## Tension de la corde pendant la préparation d'un tir (0..1).
static func _tension(h: Dictionary) -> float:
	var at = _coup(h)
	if at == null or at.phase != "startup":
		return 0.0
	return clampf(at.t / maxf(1e-3, at.dur.startup), 0.0, 1.0)

## Recul d'une arme à distance juste après le départ du trait (1 -> 0).
func _recul(h: Dictionary, genre) -> float:
	if genre == "nuee":
		return maxf(0.0, 1.0 - tir / 0.12)
	var at = _coup(h)
	if at == null or at.phase != "active":
		return 0.0
	return 1.0 - clampf(at.t / maxf(1e-3, at.dur.active), 0.0, 1.0)

## Pose le repère d'une arme (angle, taille, avance de la main) et dessine la main qui la tient.
func _poser(m: Transform2D, pose: Vector3, pr: float, main: Color, prise: float = 0.85) -> void:
	p.poser(m * Transform2D(pose.x, Vector2(pose.z, pose.z), 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2(pose.y * pr, 0.0)))
	if chaud > 0.0:
		p.lueur(Vector2(1.7 * pr, 0.0), pr * 1.6, PAL.superBar, 0.55 * chaud)
	p.disque(Vector2(prise * pr, 0.0), pr * 0.2, main, NUIT, 1.5)

func _lame(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	_poser(m, _pose(h, 0.9, genre), pr, main)
	_epee(pr, 1.0, 2.5)

## Une lame droite : garde, tranchant effilé, gouttière.
func _epee(pr: float, debut: float, bout: float) -> void:
	p.baton(Vector2((debut - 0.3) * pr, 0.0), Vector2(debut * pr, 0.0), FER, 2.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(debut * pr, -0.15 * pr), Vector2((bout - 0.35) * pr, -0.12 * pr), Vector2(bout * pr, 0.0),
		Vector2((bout - 0.35) * pr, 0.12 * pr), Vector2(debut * pr, 0.15 * pr)]), _acier, NUIT, 1.5)
	p.ligne(Vector2((debut + 0.1) * pr, 0.0), Vector2((bout - 0.45) * pr, 0.0), _fil, 1.2)
	p.baton(Vector2(debut * pr, -0.36 * pr), Vector2(debut * pr, 0.36 * pr), PAL.slashStrike, 2.5, NUIT)

## Deux dagues : la main du côté où le coup commence frappe, l'autre reste en garde ; les deux
## frappent ensemble pour le dernier coup du combo, la frappe de dash et la Colère.
func _dagues(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	var at = _coup(h)
	var sens := _sens(h)
	var deux: bool = genre != "" or (at != null and (D6Js.truthy(at.strike) or at.def.arc >= 150.0))
	for cote: float in [-1.0, 1.0]:
		var pose := Vector3(h.facing + 0.75 * cote + pas * 0.2, 0.0, 1.0)
		if h.state == "dash" or genre != "" or (at != null and (deux or cote == -sens)):
			pose = _pose(h, 0.75 * cote, genre)
			if deux and at != null and cote == sens:
				pose.x -= 0.5 * sens
		_poser(m, pose, pr, main)
		_dague(pr)

func _dague(pr: float) -> void:
	p.baton(Vector2(0.72 * pr, 0.0), Vector2(1.0 * pr, 0.0), FER, 2.5, NUIT)
	p.forme(PackedVector2Array([Vector2(1.0, -0.2) * pr, Vector2(1.55, -0.17) * pr, Vector2(1.95, 0.0) * pr, Vector2(1.0, 0.14) * pr]), _acier, NUIT, 1.5)
	p.baton(Vector2(1.0 * pr, -0.26 * pr), Vector2(1.0 * pr, 0.26 * pr), PAL.slashStrike, 2.0, NUIT)

func _hache(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	_poser(m, _pose(h, 0.9, genre), pr, main)
	var s := execution_sens if genre == "sentence" else _sens(h)
	p.baton(Vector2(0.5 * pr, 0.0), Vector2(2.55 * pr, 0.0), Color("#5d4a3a"), 3.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(1.55, 0.08 * s) * pr, Vector2(1.45, 0.78 * s) * pr, Vector2(1.9, 1.18 * s) * pr,
		Vector2(2.55, 1.1 * s) * pr, Vector2(2.82, 0.6 * s) * pr, Vector2(2.42, 0.08 * s) * pr]), _acier, NUIT, 1.5)
	p.filet(PackedVector2Array([Vector2(1.62, 0.8 * s) * pr, Vector2(1.98, 1.02 * s) * pr, Vector2(2.5, 0.95 * s) * pr]), _fil, 1.5)
	p.pic(Vector2(1.72, -0.08 * s) * pr, Vector2(2.3, -0.08 * s) * pr, Vector2(2.02, -0.5 * s) * pr, FER, NUIT, 1.5)
	p.disque(Vector2(2.0 * pr, 0.0), pr * 0.13, FER, NUIT, 1.2)

func _marteau(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	_poser(m, _pose(h, 0.9, genre), pr, main)
	p.baton(Vector2(0.5 * pr, 0.0), Vector2(2.2 * pr, 0.0), Color("#5d4a3a"), 3.5, NUIT)
	p.forme(PackedVector2Array([
		Vector2(1.9, -0.72) * pr, Vector2(2.72, -0.72) * pr, Vector2(2.84, -0.56) * pr, Vector2(2.84, 0.56) * pr,
		Vector2(2.72, 0.72) * pr, Vector2(1.9, 0.72) * pr]), _acier, NUIT, 1.5)
	for y: float in [-0.42, 0.42]:
		p.ligne(Vector2(1.94, y) * pr, Vector2(2.8, y) * pr, _fil, 1.5)
	p.forme(PackedVector2Array([Vector2(2.1, -0.2) * pr, Vector2(2.6, -0.2) * pr, Vector2(2.6, 0.2) * pr, Vector2(2.1, 0.2) * pr]), FER, Pinceau.SANS)

func _arc(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	var tension := _tension(h)
	var recul := _recul(h, genre)
	var vise: bool = _coup(h) != null or genre != ""
	var angle: float = (tir_angle if genre == "nuee" else _angle_visee(h)) if vise else h.facing + 0.4 + pas * 0.15
	_poser(m, Vector3(angle, -0.2 * recul, 1.0), pr, main, 1.55)
	var bois := Pinceau.pts_arc(Vector2(0.5 * pr, 0.0), pr * (1.2 - 0.08 * tension), -1.05 - 0.12 * tension, 1.05 + 0.12 * tension, 12)
	var encoche := Vector2(bois[0].x - tension * pr * 0.75 + recul * pr * 0.25, 0.0)
	p.filet(PackedVector2Array([bois[0], encoche, bois[12]]), PAL.slash, 1.2)
	p.ruban(bois, _acier, 3.0, NUIT)
	for i: int in [0, 12]:
		p.disque(bois[i], pr * 0.1, _fil, NUIT, 1.0)
	if tension > 0.0:
		_trait_encoche(encoche, pr * 1.6, pr)
		p.disque(encoche, pr * 0.16, main, NUIT, 1.2)

func _arbalete(h: Dictionary, pr: float, m: Transform2D, main: Color, genre) -> void:
	var tension := _tension(h)
	var recul := _recul(h, genre)
	var vise: bool = _coup(h) != null or genre != ""
	var angle: float = (tir_angle if genre == "nuee" else _angle_visee(h)) if vise else h.facing + 0.3 + pas * 0.12
	_poser(m, Vector3(angle, -0.3 * recul, 1.0), pr, main, 0.8)
	p.forme(PackedVector2Array([Vector2(0.4, -0.2) * pr, Vector2(2.1, -0.13) * pr, Vector2(2.1, 0.13) * pr, Vector2(0.4, 0.2) * pr]), Color("#5d4a3a"), NUIT, 1.5)
	p.ligne(Vector2(0.6 * pr, 0.0), Vector2(2.0 * pr, 0.0), FER, 1.5)
	var branches := Pinceau.pts_arc(Vector2(2.85 * pr, 0.0), pr * 1.05, PI - 0.95, PI + 0.95, 10)
	var noix := Vector2((1.8 - 0.8 * tension) * pr, 0.0)
	p.filet(PackedVector2Array([branches[0], noix, branches[10]]), PAL.slash, 1.2)
	p.ruban(branches, _acier, 3.5, NUIT)
	p.disque(Vector2(0.45 * pr, 0.0), pr * 0.17, FER, NUIT, 1.2)
	if tension > 0.0:
		_trait_encoche(noix, pr * 1.3, pr)

## Le trait prêt à partir (flèche, carreau) : couleur de la Lance, froide.
func _trait_encoche(depart: Vector2, longueur: float, pr: float) -> void:
	var pointe := depart + Vector2(longueur, 0.0)
	p.ligne(depart, pointe, PAL.lance, 2.0)
	p.pic(pointe + Vector2(-0.05, -0.2) * pr, pointe + Vector2(-0.05, 0.2) * pr, pointe + Vector2(0.4, 0.0) * pr, PAL.lance, NUIT, 1.2)
