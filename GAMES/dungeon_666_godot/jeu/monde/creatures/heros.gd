extends "res://jeu/monde/creatures/calque.gd"
## Calque du HÉROS : froid (blanc, cyan), cerné de bleu nuit, jamais confondu avec un ennemi.
## De dessous en dessus : l'arc du coup en cours (portée et ouverture RÉELLES du coup), le Super,
## les flammes de l'élan, la cape, les pieds, le corps, son arme (armes.gd), le geste du lancer,
## la coquille d'invulnérabilité.
##   Revenant     cimier, longue cape
##   Bourreau     cagoule à deux pointes, épaulières, carrure large
##   Chasseresse  carquois dans le dos, natte, carrure fine
## PROFONDEUR : le nœud est trié avec les ennemis et les piliers (groupe Debout d'entites.gd). Son
## rang (le y du nœud, voir _rang) le garde DEVANT tout ennemi — il ne se perd jamais sous un
## corps —, mais DERRIÈRE un pilier au nord duquel il se tient.
## Il a du POIDS : ses pieds courent à la vitesse RÉELLE, le buste se tord avec le coup, le corps
## s'étire dans l'axe du dash et s'écrase à l'arrivée, la cape traîne. Ce qui dit son état :
##   invulnérable   coquille : filet clair pendant le dash, tirets blancs après un coup reçu
##   élan (surge)   flammes d'or autour de lui, arme chauffée, double chevron : « je frappe plus fort » ;
##                  un anneau d'or se VIDE autour de lui avec la durée qui reste : « plus pour longtemps »
##   Super          Colère : il tournoie ; Sentence : il annonce puis abat chaque exécution ;
##                  Nuée : des traits d'or tournent autour de lui

const Armes = preload("res://jeu/monde/creatures/armes.gd")

const NUIT := Color("#0d2a36") # contour du héros
const ACCENT := Color("#123c4c") # détail sombre et froid de la classe
const OR := Color("#ffb02e") # élan et Super : chaud, mais jamais le rouge du danger
const CARRURE := {"bourreau": 1.14, "chasseresse": 0.86}
const CAPE := {"bourreau": 0.8, "chasseresse": 0.9}
const ELAN := 0.08 # s d'étirement au départ d'un coup
const ATTERRI := 0.1 # s d'écrasement à la sortie d'un dash
const RECUP_VISIBLE := 0.14 # s : l'arc d'un coup s'efface au début de la récupération
const GESTE := 0.22 # s : le bras reste tendu après le lancer d'une compétence
const SURGE_FONDU := 0.4 # s : l'élan s'éteint sur sa fin
const ANNEAU_ELAN := 1.42 # en rayons du héros : l'anneau de durée de l'élan, hors des flammes
const SAUT := 150.0 # u : au-delà, c'est un changement de salle, pas un pas
const EMPRISE := 3.0 # en rayons du héros : de part et d'autre d'un pilier, ce que son dessin peut toucher
const RETRAIT := 0.5 # u : son rang passe juste derrière le pied du pilier

var _armes: Armes
var _elan := 0.0
var _elan_angle := 0.0
var _atterri := 0.0
var _geste := 0.0
var _geste_angle := 0.0
var _marche := 0.0 # phase du pas (rad)
var _allure := 0.0 # 0 immobile .. 1 en pleine course
var _avant := Vector2.INF

func _init() -> void:
	super()
	_armes = Armes.new(p)

## Événements de simulation de l'image : départ d'un coup, sortie de dash, lancer, coup de Super.
func sur_evenements(liste: Array) -> void:
	for ev in liste:
		match ev.type:
			"swing":
				_elan = ELAN
				_elan_angle = ev.angle
			"dashEnd":
				_atterri = ATTERRI
			"skill":
				_geste = GESTE
				_geste_angle = ev.angle
			"superTick":
				_coup_de_super(ev)

func _coup_de_super(ev: Dictionary) -> void:
	if ev.get("super") == "sentence":
		_armes.execution = 0.0
		_armes.execution_angle = ev.angle
		_armes.execution_arc = ev.arc
		_armes.execution_sens = -1.0 if ev.get("step") == 2.0 else 1.0
	elif ev.get("super") == "nuee":
		_armes.tir = 0.0
		_armes.tir_angle = ev.angle

func actualiser(delta: float) -> void:
	_elan = maxf(0.0, _elan - delta)
	_atterri = maxf(0.0, _atterri - delta)
	_geste = maxf(0.0, _geste - delta)
	_armes.execution += delta
	_armes.tir += delta
	var g = jeu()
	if g != null:
		_pas(g, delta)
		position.y = _rang(g, lieu_heros(g))
	queue_redraw()

## Rang de profondeur du héros (le y du nœud ; le dessin est décalé d'autant, voir _draw) : devant
## tout, sauf derrière les piliers dont il est juste au nord. En plein Bond il passe au-dessus.
func _rang(g: Dictionary, pos: Vector2) -> float:
	var rang: float = g.room.h
	if envol_heros(g) > 0.0:
		return rang
	var portee: float = g.player.r * EMPRISE
	for o in g.room.obstacles:
		if pos.y < o.y0 and pos.x > o.x0 - portee and pos.x < o.x1 + portee:
			rang = minf(rang, o.y1 - RETRAIT)
	return rang

## Distance réellement parcourue depuis la dernière image : elle fait avancer le pas de course.
func _pas(g: Dictionary, delta: float) -> void:
	var h: Dictionary = g.player
	var pos := lieu_heros(g)
	var d := 0.0 if _avant == Vector2.INF else pos.distance_to(_avant)
	_avant = pos
	if d > SAUT:
		d = 0.0
	var court: bool = h.state == "free" or h.state == "attack" or h.state == "super"
	var vise := clampf(d / maxf(1e-4, delta) / (0.7 * g.tuning.player.speed), 0.0, 1.0) if court else 0.0
	_allure = lerpf(_allure, vise, 1.0 - exp(-14.0 * delta))
	_marche += d * PI / (h.r * 2.6)

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	var h: Dictionary = g.player
	var pos := lieu_heros(g) - position
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
	var elan: float = 0.0 if h.state == "dead" else minf(1.0, nombre(h, "surge") / SURGE_FONDU)
	p.poser(m)
	if elan > 0.0:
		_flammes(pr, elan)
	_cape(h, pr, classe)
	_pieds(h, pr, m)
	p.poser(m * Transform2D(_buste(g, h), Vector2.ZERO))
	_corps(g, h, pr, classe)
	_armes.temps = temps()
	_armes.pas = sin(_marche) * _allure
	_armes.chaud = elan
	_armes.dessiner(g, h, pr, m, PAL.heroHurt if h.hurtFlash > 0.0 else PAL.hero)
	_lancer(g, h, pr, m)
	p.poser(m)
	_coquille(h, pr, elan)
	p.alpha = 1.0
	p.lever()

func _classe(g: Dictionary) -> String:
	var kit = g.get("kit")
	return str(kit.get("classId")) if kit is Dictionary else "revenant"

## Étirement (dash, départ d'un coup, course) et écrasement (sortie de dash), aire conservée.
func _repere(h: Dictionary, pos: Vector2) -> Transform2D:
	if h.state == "dead":
		return Transform2D(-1.2 * minf(1.0, h.stateTime * 2.0), Vector2.ONE * maxf(0.3, 1.0 - 0.5 * h.stateTime), 0.0, pos)
	var etire := 1.0
	var axe: float = h.facing
	var vitesse := Vector2(h.vx, h.vy)
	if h.state == "dash":
		etire = 1.5
		axe = Vector2(h.dashDirX, h.dashDirY).angle()
	elif _atterri > 0.0:
		etire = 1.0 - 0.24 * sin(PI * _atterri / ATTERRI)
		axe = Vector2(h.dashDirX, h.dashDirY).angle()
	elif _elan > 0.0:
		etire = 1.0 + 0.2 * _elan / ELAN
		axe = _elan_angle
	elif vitesse.length() > 30.0:
		etire = 1.0 + 0.06 * _allure
		axe = vitesse.angle()
	return Transform2D(0.0, pos) * Transform2D(axe, Vector2.ZERO) * Transform2D(0.0, Vector2(etire, 1.0 / etire), 0.0, Vector2.ZERO) * Transform2D(-axe, Vector2.ZERO)

## Angle du buste : le regard, tordu par la course (les épaules roulent) et par le coup en cours
## (il arme d'un côté, finit de l'autre). Pendant la Colère, il tournoie.
func _buste(g: Dictionary, h: Dictionary) -> float:
	if h.state == "super" and g.tuning["super"].get("kind") == "colere":
		return temps() * 16.0
	var at = h.get("attack")
	if h.state != "attack" or not (at is Dictionary) or D6Js.truthy(at.def.get("shot")):
		return h.facing + sin(_marche) * 0.16 * _allure
	var sens := -1.0 if int(at.index) % 2 == 1 else 1.0
	match at.phase:
		"startup":
			return h.facing - 0.4 * sens * clampf(at.t / maxf(1e-3, at.dur.startup), 0.0, 1.0)
		"active":
			return h.facing + sens * lerpf(-0.4, 0.45, clampf(at.t / maxf(1e-3, at.dur.active), 0.0, 1.0))
	return h.facing + 0.45 * sens * (1.0 - clampf(at.t / maxf(1e-3, at.dur.recovery), 0.0, 1.0))

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
			_taillade(portee, a0, lerpf(a0, a1, maxf(0.15, 1.0 - (1.0 - k) * (1.0 - k))), epais, teinte, 1.0)
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

## Super en cours, sous le héros. Colère : le tourbillon à sa portée réelle. Sentence : l'arc d'or
## de la prochaine exécution se charge, à sa portée et à son ouverture réelles. Nuée : une ronde
## de traits d'or.
func _super(g: Dictionary, h: Dictionary, pr: float) -> void:
	if h.state != "super":
		return
	var s: Dictionary = g.tuning["super"]
	var t0 := temps() * 15.0
	match s.get("kind"):
		"colere":
			for i in 2:
				p.taillade(Vector2.ZERO, s.radius, t0 + i * PI, t0 + i * PI + 2.3, s.radius * 0.42, PAL.superBar, 0.8)
			p.anneau(Vector2.ZERO, s.radius, Color(PAL.superBar, 0.45), 2.0)
		"sentence":
			_annonce_sentence(h, s)
			p.pointille(Vector2.ZERO, pr * 2.3, PAL.superBar, 3.0, 16.0, t0 * 0.4)
		_:
			p.pointille(Vector2.ZERO, pr * 2.3, PAL.superBar, 3.0, 16.0, t0 * 0.4)
			for i in 6:
				var d := Vector2.from_angle(t0 * 0.3 + i * TAU / 6.0)
				p.pic(d * pr * 2.9 + d.orthogonal() * 3.5, d * pr * 2.9 - d.orthogonal() * 3.5, d * pr * 3.9, PAL.crit, NUIT, 1.2)
	p.anneau(Vector2.ZERO, pr * 1.7, Color(PAL.crit, 0.6 + 0.3 * sin(t0)), 2.0)

## Sentence : avant chaque exécution, son secteur (portée et ouverture de tuning.super.strikes)
## se dessine en or devant le Bourreau et s'épaissit jusqu'à l'instant du coup.
func _annonce_sentence(h: Dictionary, s: Dictionary) -> void:
	var coups: Array = s.strikes
	var rang := int(nombre(h, "superStep"))
	if rang >= coups.size():
		return
	var depuis: float = coups[rang - 1].at if rang > 0 else 0.0
	var k := clampf((nombre(h, "superClock") - depuis) / maxf(1e-3, coups[rang].at - depuis), 0.0, 1.0)
	var demi: float = deg_to_rad(coups[rang].arc) * 0.5
	var teinte := Color(OR, 0.15 + 0.6 * k)
	p.arc(Vector2.ZERO, coups[rang].range, h.facing - demi, h.facing + demi, teinte, 1.5 + 3.0 * k)
	if demi < PI - 0.01:
		for s2: float in [-1.0, 1.0]:
			var d := Vector2.from_angle(h.facing + demi * s2)
			draw_line(d * coups[rang].range * 0.55, d * coups[rang].range, teinte, 1.5)

# ------------------------------------------------------------------ corps

## Cape : elle flotte à l'opposé du regard et du mouvement, s'allonge avec la vitesse, et file
## droit derrière lui, longue et serrée, pendant le dash.
func _cape(h: Dictionary, pr: float, classe: String) -> void:
	var vitesse := Vector2(h.vx, h.vy)
	var dash: bool = h.state == "dash"
	var dir := -Vector2.from_angle(h.facing) * 0.75 - vitesse / 420.0
	if dash:
		dir = -Vector2(h.dashDirX, h.dashDirY)
	dir = dir.normalized() if dir.length() > 0.05 else -Vector2.from_angle(h.facing)
	var longueur: float = pr * (2.4 if dash else 1.35 + minf(1.0, vitesse.length() / 400.0) * 0.9) * CAPE.get(classe, 1.0)
	var bat := 0.12 + 0.14 * _allure
	var epine := PackedVector2Array()
	var demi := PackedFloat32Array()
	for i in 6:
		var u := i / 5.0
		var onde := sin(temps() * (16.0 if dash else 10.0) - u * 4.0) * pr * bat * u
		epine.append(dir * longueur * u + dir.orthogonal() * onde)
		demi.append(pr * lerpf(0.88, 0.3 if dash else 0.42, u * u))
	var teinte: Color = PAL.heroHurt.darkened(0.3) if h.hurtFlash > 0.0 else PAL.heroCape
	p.bande(epine, demi, teinte, NUIT, 2.0)
	p.ligne(epine[1], epine[4], teinte.darkened(0.25), 1.5)

## Les pieds : ils passent l'un devant l'autre au rythme de la distance parcourue, dans l'axe du
## déplacement ; ramenés en arrière pendant le dash.
func _pieds(h: Dictionary, pr: float, m: Transform2D) -> void:
	if h.state == "dead":
		return
	var vitesse := Vector2(h.vx, h.vy)
	var dash: bool = h.state == "dash"
	var axe: float = Vector2(h.dashDirX, h.dashDirY).angle() if dash else (vitesse.angle() if vitesse.length() > 30.0 else h.facing)
	p.poser(m * Transform2D(axe, Vector2.ZERO))
	var pas: float = sin(_marche) * 0.9 * _allure
	for s: float in [-1.0, 1.0]:
		var x := -0.7 if dash else 0.05 + pas * s
		p.ellipse(Vector2(x * pr, 0.42 * s * pr), pr * 0.42, pr * 0.27, ACCENT, NUIT, 2.0, 0.0, 12)

func _corps(g: Dictionary, h: Dictionary, pr: float, classe: String) -> void:
	var touche: bool = h.hurtFlash > 0.0
	var clair: Color = PAL.heroHurt if touche else PAL.hero
	var lisere: Color = PAL.heroHurt.darkened(0.35) if touche else PAL.heroCape
	var carrure: float = pr * CARRURE.get(classe, 1.0)
	_dos(classe, pr)
	p.ellipse(Vector2(-0.1 * pr, 0.0), pr * 0.62, carrure, lisere.darkened(0.12), NUIT, 2.0)
	if classe == "bourreau":
		for s: float in [-1.0, 1.0]:
			p.disque(Vector2(-0.1 * pr, carrure * 0.8 * s), pr * 0.34, ACCENT, NUIT, 2.0)
	_main_libre(g, h, pr, carrure, clair)
	var penche := 0.2 if h.state == "dash" else 0.1 * _allure
	var tete := Vector2((0.06 + penche) * pr, 0.0)
	var hr := pr * 0.72
	p.disque(tete, hr, clair, lisere, 3.0)
	p.calotte(tete + Vector2(hr * 0.3, 0.0), hr * 0.62, -1.2, 1.2, NUIT)
	p.ligne(tete + Vector2(hr * 0.72, -hr * 0.2), tete + Vector2(hr * 0.72, hr * 0.2), PAL.slashStrike, 1.5)
	_coiffe(classe, tete, hr)

## La main qui ne tient pas l'arme (lame, hache, maillet) : elle balance à contretemps du pas.
## Elle disparaît pendant un lancer : c'est elle qui lance (voir _lancer).
func _main_libre(g: Dictionary, h: Dictionary, pr: float, carrure: float, clair: Color) -> void:
	var kit = g.get("kit")
	var type = kit.get("weaponType") if kit is Dictionary else "lame"
	if type in ["dagues", "arc", "arbalete"] or _geste > 0.0 or h.state == "cast":
		return
	p.disque(Vector2((0.3 - sin(_marche) * 0.55 * _allure) * pr, -carrure * 0.8), pr * 0.2, clair, NUIT, 1.5)

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
			var onde := sin(temps() * 10.0 + _marche) * hr * (0.2 + 0.3 * _allure)
			p.ruban(PackedVector2Array([tete + Vector2(-hr * 0.8, 0.0), tete + Vector2(-hr * 1.5, onde * 0.5), tete + Vector2(-hr * 2.2, onde)]), PAL.heroCape, 3.0, NUIT)
		_:
			p.baton(tete + Vector2(-hr * 0.95, 0.0), tete + Vector2(hr * 0.1, 0.0), PAL.heroCape, 2.5, NUIT)

# ------------------------------------------------------------------ états

## Lancer d'une compétence : la main libre se tend dans l'axe du lancer, une étoile froide s'y
## charge (état `cast`), puis un trait de lumière part et le bras reste tendu un instant.
func _lancer(g: Dictionary, h: Dictionary, pr: float, m: Transform2D) -> void:
	var sort = h.get("cast")
	var bond: bool = sort is Dictionary and sort.get("kind") == "bond"
	var charge := 0.0
	var angle := _geste_angle
	if h.state == "cast" and not bond:
		charge = 1.0 - clampf(h.castT / maxf(1e-3, nombre(g.tuning.skill, "castTime")), 0.0, 1.0)
		angle = Vector2(h.castDirX, h.castDirY).angle()
	elif _geste <= 0.0 or bond:
		return
	var k := maxf(charge, _geste / GESTE)
	p.poser(m * Transform2D(angle, Vector2.ZERO))
	var main := Vector2(pr * (1.0 + 0.55 * k), 0.0)
	p.lueur(main, pr * (1.4 + 1.4 * k), PAL.lance, 0.9 * k)
	if _geste > 0.0:
		var c := Color(PAL.lance, 0.8 * k)
		draw_primitive(PackedVector2Array([main + Vector2(0.0, -6.0), main + Vector2(pr * 4.5 * k, 0.0), main + Vector2(0.0, 6.0)]),
			PackedColorArray([Color(c, 0.0), c, Color(c, 0.0)]), PackedVector2Array())
	p.etoile(main + Vector2(pr * 0.3, 0.0), pr * 0.55 * k, PAL.lance, temps() * 8.0, Pinceau.SANS)
	p.disque(main, pr * 0.22, PAL.hero, NUIT, 1.5)

## Invulnérable : une coquille autour de lui (filet clair étiré avec le dash ; tirets blancs qui
## tournent après un coup reçu). En élan : anneau de durée et double chevron au-dessus de la tête.
func _coquille(h: Dictionary, pr: float, elan: float) -> void:
	if h.state == "dead":
		return
	if h.state == "dash":
		p.anneau(Vector2.ZERO, pr * 1.45, Color(PAL.slash, 0.75), 1.5)
	elif h.iframes > 0.0 and h.state != "super":
		p.pointille(Vector2.ZERO, pr * 1.55, Color(PAL.hero, 0.9), 2.0, 9.0, temps() * 5.0)
	if elan <= 0.0:
		return
	_anneau_elan(h, pr * ANNEAU_ELAN, elan)
	var monte := fposmod(temps() * 1.6, 1.0) * 4.0
	for i in 2:
		var y := -pr * (2.0 + 0.42 * i) - monte
		var pts := PackedVector2Array([Vector2(-6.0, y + 5.0), Vector2(0.0, y), Vector2(6.0, y + 5.0)])
		p.filet(pts, Color(NUIT, elan), 5.5)
		p.filet(pts, Color(PAL.crit, elan), 2.5)

## L'élan se lit S'ÉPUISER : sa piste reste, sombre ; l'arc d'or cerné qui la recouvre se vide
## dans le sens des aiguilles d'une montre (comme la flaque qui brûle, contours.gd) à mesure que
## `player.surge` retombe, une perle claire à sa tête. Plein = la durée posée par la bénédiction.
func _anneau_elan(h: Dictionary, rayon: float, elan: float) -> void:
	var reste := clampf(nombre(h, "surge") / _elan_plein(h), 0.0, 1.0)
	var a0 := -PI / 2.0
	var a1 := a0 + TAU * reste
	p.anneau(Vector2.ZERO, rayon, Color(NUIT, 0.45 * elan), 3.5)
	p.anneau(Vector2.ZERO, rayon, Color(PAL.crit, 0.22 * elan), 1.5)
	p.arc(Vector2.ZERO, rayon, a0, a1, Color(NUIT, elan), 6.0)
	p.arc(Vector2.ZERO, rayon, a0, a1, Color(PAL.crit, elan), 3.0)
	p.disque(Vector2.from_angle(a1) * rayon, 3.2, Color(PAL.hero, elan), Color(NUIT, elan), 1.5)

## Durée pleine de l'élan (s) : la plus longue que posent les procs « surge » du héros, LUE dans
## l'état (aucune durée recopiée ici) ; à défaut de proc, ce qu'il en reste : l'anneau est plein.
func _elan_plein(h: Dictionary) -> float:
	var plein := maxf(1e-3, nombre(h, "surge"))
	for pr in h.get("procs", []):
		if pr is Dictionary and pr.get("effect") == "surge":
			plein = maxf(plein, nombre(pr, "duration"))
	return plein

## Flammes de l'élan (« Représailles ») : des langues d'or montent autour de lui, sous le corps.
func _flammes(pr: float, elan: float) -> void:
	for i in 7:
		var base := Vector2.from_angle(i * TAU / 7.0 + temps() * 0.7) * pr * 1.0
		var hauteur := pr * (0.9 + 0.4 * sin(temps() * 13.0 + i * 2.3)) * elan
		var pointe := base + Vector2(sin(temps() * 9.0 + i) * pr * 0.18, -hauteur)
		var large := Vector2(pr * 0.34, 0.0)
		p.forme(PackedVector2Array([base - large, pointe, base + large]), Color(OR, 0.9), Pinceau.SANS)
		p.forme(PackedVector2Array([base - large * 0.5, base.lerp(pointe, 0.6), base + large * 0.5]), PAL.crit, Pinceau.SANS)
