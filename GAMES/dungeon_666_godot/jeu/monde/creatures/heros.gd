extends "res://jeu/monde/creatures/calque.gd"
## Calque du HÉROS : froid (blanc, cyan), cerné de bleu nuit, jamais confondu avec un ennemi.
## De dessous en dessus : l'arc du coup en cours (portée et ouverture RÉELLES du coup), le Super,
## la cape, le corps (épaules, tête, visière), la marque de sa classe, son arme (armes.gd).
##   Revenant     cimier, longue cape
##   Bourreau     cagoule à deux pointes, épaulières, carrure large
##   Chasseresse  carquois dans le dos, natte, carrure fine

const Armes = preload("res://jeu/monde/creatures/armes.gd")

const NUIT := Color("#0d2a36") # contour du héros
const ACCENT := Color("#123c4c") # détail sombre et froid de la classe
const CARRURE := {"bourreau": 1.14, "chasseresse": 0.86}
const CAPE := {"bourreau": 0.8, "chasseresse": 0.9}
const ELAN := 0.05 # s d'étirement au départ d'un coup
const ATTERRI := 0.067 # s d'écrasement à la sortie d'un dash
const RECUP_VISIBLE := 0.14 # s : l'arc d'un coup s'efface au début de la récupération

var _armes: Armes
var _elan := 0.0
var _elan_angle := 0.0
var _atterri := 0.0

func _init() -> void:
	super()
	_armes = Armes.new(p)

## Événements de simulation de l'image : départ d'un coup, sortie de dash.
func sur_evenements(liste: Array) -> void:
	for ev in liste:
		if ev.type == "swing":
			_elan = ELAN
			_elan_angle = ev.angle
		elif ev.type == "dashEnd":
			_atterri = ATTERRI

func _process(delta: float) -> void:
	_elan = maxf(0.0, _elan - delta)
	_atterri = maxf(0.0, _atterri - delta)

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	var h: Dictionary = g.player
	var pos := lieu_heros(g)
	var pr: float = h.r * HEROS_VISUEL
	var classe: String = _classe(g)
	p.alpha = 1.0 if h.state != "dead" else alpha_heros(h)
	p.poser(Transform2D(0.0, pos))
	_coup(h)
	_super(g, h, pr)
	p.alpha = alpha_heros(h)
	var haut := envol_heros(g)
	var m := _repere(h, pos - Vector2(0.0, haut * BOND_HAUTEUR))
	pr *= 1.0 + 0.15 * haut
	p.poser(m)
	_cape(h, pr, classe)
	p.poser(m * Transform2D(h.facing, Vector2.ZERO))
	_corps(h, pr, classe)
	_armes.dessiner(g, h, pr, m, PAL.heroHurt if h.hurtFlash > 0.0 else PAL.hero)
	p.alpha = 1.0
	p.lever()

func _classe(g: Dictionary) -> String:
	var kit = g.get("kit")
	return str(kit.get("classId")) if kit is Dictionary else "revenant"

## Étirement (dash, départ d'un coup) et écrasement (sortie de dash), aire conservée.
func _repere(h: Dictionary, pos: Vector2) -> Transform2D:
	var etire := 1.0
	var axe: float = h.facing
	if h.state == "dash":
		etire = 1.35
		axe = Vector2(h.dashDirX, h.dashDirY).angle()
	elif _atterri > 0.0:
		etire = 0.82
		axe = Vector2(h.dashDirX, h.dashDirY).angle()
	elif _elan > 0.0:
		etire = 1.18
		axe = _elan_angle
	if h.state == "dead":
		return Transform2D(0.0, Vector2.ONE * maxf(0.3, 1.0 - 0.5 * h.stateTime), 0.0, pos)
	return Transform2D(0.0, pos) * Transform2D(axe, Vector2.ZERO) * Transform2D(0.0, Vector2(etire, 1.0 / etire), 0.0, Vector2.ZERO) * Transform2D(-axe, Vector2.ZERO)

# ------------------------------------------------------------------ coups

## Arc du coup de mêlée en cours, lu dans l'état : annoncé (startup), balayé (active), dissipé (recovery).
func _coup(h: Dictionary) -> void:
	var at = h.get("attack")
	if h.state != "attack" or not (at is Dictionary) or D6Js.truthy(at.def.get("shot")):
		return
	var portee: float = at.def.range
	var ouverture: float = deg_to_rad(at.def.arc)
	var sens := -1.0 if int(at.index) % 2 == 1 else 1.0
	var a0: float = at.angle - ouverture * 0.5 * sens
	var a1: float = a0 + ouverture * sens
	var frappe: bool = D6Js.truthy(at.strike)
	var teinte: Color = PAL.slashStrike if frappe else PAL.slash
	var epais: float = portee * (0.5 if frappe or at.def.arc >= 200.0 else 0.38)
	match at.phase:
		"startup":
			var k: float = clampf(at.t / maxf(1e-3, at.dur.startup), 0.0, 1.0)
			p.arc(Vector2.ZERO, portee, a0, a1, Color(teinte, 0.1 + 0.3 * k), 1.5)
		"active":
			var k: float = clampf(at.t / maxf(1e-3, at.dur.active), 0.0, 1.0)
			_taillade(portee, a0, lerpf(a0, a1, maxf(0.15, k)), epais, teinte, 1.0)
			if frappe:
				_estoc(at.angle, portee, 1.0)
		"recovery":
			var reste: float = 1.0 - at.t / minf(RECUP_VISIBLE, maxf(1e-3, at.dur.recovery))
			if reste > 0.0:
				_taillade(portee, a0, a1, epais * (0.4 + 0.6 * reste), teinte, reste)
				if frappe:
					_estoc(at.angle, portee, reste)

func _taillade(portee: float, a0: float, a1: float, epais: float, teinte: Color, force: float) -> void:
	p.taillade(Vector2.ZERO, portee, a0, a1, epais, teinte, 0.92 * force)
	p.arc(Vector2.ZERO, portee, a0, a1, Color(PAL.heroCape, 0.7 * force), 2.5)

## Frappe de dash : une pointe de lumière dans l'axe, jusqu'au bout de la portée.
func _estoc(angle: float, portee: float, force: float) -> void:
	var d := Vector2.from_angle(angle)
	var c := Color(PAL.lance, 0.75 * force)
	draw_primitive(PackedVector2Array([d.orthogonal() * 9.0, d * portee * 1.04, -d.orthogonal() * 9.0]),
		PackedColorArray([Color(c, 0.0), c, Color(c, 0.0)]), PackedVector2Array())

## Super en cours : la Colère tourbillonne à sa portée réelle ; les autres ceignent le héros d'or.
func _super(g: Dictionary, h: Dictionary, pr: float) -> void:
	if h.state != "super":
		return
	var s: Dictionary = g.tuning["super"]
	var t0 := temps() * 15.0
	if s.get("kind") == "colere":
		for i in 2:
			p.taillade(Vector2.ZERO, s.radius, t0 + i * PI, t0 + i * PI + 2.3, s.radius * 0.42, PAL.superBar, 0.8)
		p.anneau(Vector2.ZERO, s.radius, Color(PAL.superBar, 0.45), 2.0)
	else:
		p.pointille(Vector2.ZERO, pr * 2.3, PAL.superBar, 3.0, 16.0, t0 * 0.4)
		p.anneau(Vector2.ZERO, pr * 1.7, Color(PAL.crit, 0.6 + 0.3 * sin(t0)), 2.0)

# ------------------------------------------------------------------ corps

## Cape : elle flotte à l'opposé du regard et du mouvement, et s'allonge avec la vitesse.
func _cape(h: Dictionary, pr: float, classe: String) -> void:
	var vitesse := Vector2(h.vx, h.vy)
	var dir := -Vector2.from_angle(h.facing) * 0.75 - vitesse / 420.0
	dir = dir.normalized() if dir.length() > 0.05 else -Vector2.from_angle(h.facing)
	var longueur: float = pr * (1.35 + minf(1.0, vitesse.length() / 400.0) * 0.9) * CAPE.get(classe, 1.0)
	var epine := PackedVector2Array()
	var demi := PackedFloat32Array()
	for i in 6:
		var u := i / 5.0
		var onde := sin(temps() * 10.0 - u * 4.0) * pr * 0.2 * u
		epine.append(dir * longueur * u + dir.orthogonal() * onde)
		demi.append(pr * lerpf(0.88, 0.42, u * u))
	var teinte: Color = PAL.heroHurt.darkened(0.3) if h.hurtFlash > 0.0 else PAL.heroCape
	p.bande(epine, demi, teinte, NUIT, 2.0)
	p.ligne(epine[1], epine[4], teinte.darkened(0.25), 1.5)

func _corps(h: Dictionary, pr: float, classe: String) -> void:
	var touche: bool = h.hurtFlash > 0.0
	var clair: Color = PAL.heroHurt if touche else PAL.hero
	var lisere: Color = PAL.heroHurt.darkened(0.35) if touche else PAL.heroCape
	var carrure: float = pr * CARRURE.get(classe, 1.0)
	_dos(classe, pr)
	p.ellipse(Vector2(-0.1 * pr, 0.0), pr * 0.62, carrure, lisere.darkened(0.12), NUIT, 2.0)
	if classe == "bourreau":
		for s: float in [-1.0, 1.0]:
			p.disque(Vector2(-0.1 * pr, carrure * 0.8 * s), pr * 0.34, ACCENT, NUIT, 2.0)
	var tete := Vector2(0.06 * pr, 0.0)
	var hr := pr * 0.72
	p.disque(tete, hr, clair, lisere, 3.0)
	p.calotte(tete + Vector2(hr * 0.3, 0.0), hr * 0.62, -1.2, 1.2, NUIT)
	p.ligne(tete + Vector2(hr * 0.72, -hr * 0.2), tete + Vector2(hr * 0.72, hr * 0.2), PAL.slashStrike, 1.5)
	_coiffe(classe, tete, hr)

## Ce que la classe porte dans le dos (sous les épaules).
func _dos(classe: String, pr: float) -> void:
	if classe != "chasseresse":
		return
	var axe := Vector2.from_angle(PI + 0.5)
	var cote := axe.orthogonal() * pr * 0.24
	p.forme(PackedVector2Array([axe * pr * 0.3 + cote, axe * pr * 1.35 + cote, axe * pr * 1.35 - cote, axe * pr * 0.3 - cote]), ACCENT, NUIT, 2.0)
	for i in 3:
		var pied: Vector2 = axe * pr * 1.35 + cote * (i - 1) * 0.6
		p.ligne(pied, pied + axe * pr * 0.3, PAL.hero, 1.5)

## Ce que la classe porte sur la tête : cimier, cagoule à pointes, natte.
func _coiffe(classe: String, tete: Vector2, hr: float) -> void:
	match classe:
		"bourreau":
			p.calotte(tete, hr * 0.98, 1.5, TAU - 1.5, ACCENT)
			for s: float in [-1.0, 1.0]:
				var a := PI + 0.75 * s
				p.pic(tete + Vector2.from_angle(a - 0.3) * hr * 0.9, tete + Vector2.from_angle(a + 0.3) * hr * 0.9, tete + Vector2.from_angle(a) * hr * 1.55, ACCENT, NUIT, 1.5)
		"chasseresse":
			var onde := sin(temps() * 10.0) * hr * 0.2
			p.ruban(PackedVector2Array([tete + Vector2(-hr * 0.8, 0.0), tete + Vector2(-hr * 1.5, onde * 0.5), tete + Vector2(-hr * 2.2, onde)]), PAL.heroCape, 3.0, NUIT)
		_:
			p.baton(tete + Vector2(-hr * 0.95, 0.0), tete + Vector2(hr * 0.1, 0.0), PAL.heroCape, 2.5, NUIT)
