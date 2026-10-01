extends RefCounted
## Les 7 premiers ARCHÉTYPES d'ennemis, une fonction par créature (les trois suivants : nouveaux.gd).
## Repère déjà posé par le corps (corps.gd) : origine au centre de l'ennemi, x = devant lui,
## y = son côté droit. `r` = son rayon, `corps` = sa couleur (ou celle du flash d'impact) ; les
## ombres du corps en sont dérivées. Le corps donne aussi son pas (`n.marche`, `n.allure`) et la
## part écoulée de son télégraphe (`n.anticipation`) : les membres en vivent.
## Silhouettes, pour les reconnaître d'un coup d'œil :
##   diablotin   petit, ailes de chauve-souris, queue fourchue
##   brute       massive, deux poings énormes, défenses
##   archer      crâne sous capuche, arc devant lui
##   bélier      corps allongé, grandes cornes d'ivoire en avant
##   possédé     boule fissurée aux yeux exorbités, qui gonfle et blanchit avant d'exploser
##   pyromancienne  capuche pointue, bâton à flamme
##   nécromancien   robe dentelée, crâne, éclats d'os en orbite

const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL
const IVOIRE := Color("#f0e0c0")
const CORNE := Color("#ffd9a8")
const OSSEMENT := Color("#e8e0d0")
const BOIS := Color("#8a6a4a")
const ORBITE := Color("#1a0a0c")

var p: Pinceau
var temps := 0.0
## Le corps en cours de dessin (corps.gd) : son pas, son allure, son anticipation.
var n: Node2D
## Le haut et la droite de l'écran, exprimés dans le repère tourné de la créature (flammes, hampe).
var haut := Vector2.UP
var droite := Vector2.RIGHT

func _init(pinceau: Pinceau) -> void:
	p = pinceau

func dessiner(e: Dictionary, r: float, corps: Color, g: Dictionary, noeud: Node2D, horloge: float) -> void:
	_poser_corps(noeud, horloge)
	match e.kind:
		"brute": brute(e, r, corps)
		"archer": archer(e, r, corps)
		"charger": belier(e, r, corps)
		"exploder": possede(e, r, corps, g)
		"pyromancer": pyromancienne(e, r, corps)
		"necromancer": necromancien(e, r, corps)
		_: diablotin(e, r, corps)

func _poser_corps(noeud: Node2D, horloge: float) -> void:
	n = noeud
	temps = horloge
	haut = Vector2.UP.rotated(-n.rotation)
	droite = Vector2.RIGHT.rotated(-n.rotation)

## Deux pieds sous le corps, qui passent l'un devant l'autre au rythme du pas.
func pieds(r: float, ecart: float, teinte: Color) -> void:
	var pas: float = sin(n.marche) * 0.8 * n.allure
	for s: float in [-1.0, 1.0]:
		p.ellipse(Vector2((0.12 + pas * s) * r, ecart * s * r), r * 0.36, r * 0.25, teinte, Pinceau.ENCRE, 2.0, 0.0, 12)

func diablotin(e: Dictionary, r: float, corps: Color) -> void:
	var sombre := corps.darkened(0.42)
	var arme: float = n.anticipation
	var fonce: bool = e.state == "strike"
	var bat: float = -0.5 if fonce else sin(temps * (9.0 + 7.0 * n.allure) + e.id) * 0.18 + 0.3 * arme
	var fouet: float = sin(temps * 7.0 + e.id * 1.7) * (0.1 if fonce else 0.3)
	p.ruban(PackedVector2Array([Vector2(-0.8, 0.0) * r, Vector2(-1.3, fouet * 0.5) * r, Vector2(-1.75, fouet) * r]), sombre, r * 0.16)
	p.pic(Vector2(-1.68, fouet - 0.24) * r, Vector2(-1.68, fouet + 0.24) * r, Vector2(-2.2, fouet * 1.2) * r, sombre)
	for s: float in [-1.0, 1.0]:
		p.forme(PackedVector2Array([
			Vector2(-0.05, 0.7 * s) * r, Vector2(-0.3, (1.95 + bat) * s) * r, Vector2(-0.75, (1.35 + bat) * s) * r,
			Vector2(-1.3, (1.6 + bat) * s) * r, Vector2(-1.0, 0.4 * s) * r]), sombre, Pinceau.ENCRE, 2.0)
		p.pic(Vector2(0.3, 0.78 * s) * r, Vector2(0.78, 0.5 * s) * r, Vector2(1.25 + 0.2 * arme, 1.0 * s) * r, CORNE, Pinceau.ENCRE, 1.5)
	p.disque(Vector2.ZERO, r, corps)
	p.yeux(Vector2.ZERO, r, Color("#ffe14a"), 0.5, 0.52, 0.17 + 0.05 * arme)

func brute(e: Dictionary, r: float, corps: Color) -> void:
	var sombre := corps.darkened(0.18)
	var arme: bool = e.state == "windup"
	var abattu: bool = e.state == "recover"
	var k: float = n.anticipation
	var ouverture := lerpf(1.3, 0.75, k) if arme else (0.45 if abattu else 1.3)
	var allonge := lerpf(0.9, 1.2, k) if arme else (1.3 if abattu else 0.9)
	pieds(r, 0.55, corps.darkened(0.55))
	for s: float in [-1.0, 1.0]:
		p.pic(Vector2(-0.75, 0.45 * s) * r, Vector2(-0.3, 0.9 * s) * r, Vector2(-0.95, 1.15 * s) * r, corps.darkened(0.4))
	for s: float in [-1.0, 1.0]:
		var ballant: float = sin(n.marche) * 0.22 * n.allure * s
		var poing: Vector2 = Vector2.from_angle(ouverture * s + ballant) * r * allonge
		p.disque(poing, r * (0.45 + 0.06 * k), sombre, Pinceau.ENCRE, 3.0)
		p.arc(poing, r * 0.27, -0.9, 0.9, corps.darkened(0.6), 2.0)
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	p.calotte(Vector2.ZERO, r * 0.94, -1.05, 1.05, corps.darkened(0.5))
	for s: float in [-1.0, 1.0]:
		p.pic(Vector2(0.78, 0.2 * s) * r, Vector2(0.72, 0.52 * s) * r, Vector2(1.28, 0.44 * s) * r, IVOIRE, Pinceau.ENCRE, 1.5)
	p.yeux(Vector2.ZERO, r, Color("#ffb03a"), 0.36, 0.7, 0.11)

func archer(e: Dictionary, r: float, corps: Color) -> void:
	var capuche := Color("#6b4f3e")
	var tension: float = n.anticipation if e.state == "windup" else 0.0
	var pan := Pinceau.pts_arc(Vector2.ZERO, r * 1.14, 1.35, 2.75, 6)
	pan.append(Vector2(-1.8, sin(n.marche) * 0.3 * n.allure) * r)
	pan.append_array(Pinceau.pts_arc(Vector2.ZERO, r * 1.14, TAU - 2.75, TAU - 1.35, 6))
	p.forme(pan, capuche)
	p.disque(Vector2.ZERO, r, corps)
	p.calotte(Vector2.ZERO, r * 0.95, 1.85, TAU - 1.85, capuche)
	for s: float in [-0.44, 0.44]:
		p.disque(Vector2.from_angle(s) * r * 0.5, r * 0.22, ORBITE, Pinceau.SANS)
	p.yeux(Vector2.ZERO, r, PAL.danger, 0.44, 0.52, 0.1)
	_arc_squelette(r, tension)

## L'arc de l'archer : la corde recule et la flèche (orange : elle fait mal) paraît pendant la visée.
func _arc_squelette(r: float, tension: float) -> void:
	var centre := Vector2(r * (0.6 - 0.3 * tension), 0.0)
	var bois := Pinceau.pts_arc(centre, r * 0.95, -1.1, 1.1, 12)
	var encoche := Vector2(bois[0].x - tension * r * 0.75, 0.0)
	p.filet(PackedVector2Array([bois[0], encoche, bois[12]]), Color("#d8d0c0"), 1.2)
	p.ruban(bois, BOIS, 2.6)
	if tension > 0.0:
		var pointe := encoche + Vector2(r * 1.9, 0.0)
		p.ligne(encoche, pointe, PAL.arrow, 2.0)
		p.pic(pointe + Vector2(-0.1, -0.24) * r, pointe + Vector2(-0.1, 0.24) * r, pointe + Vector2(0.42, 0.0) * r, PAL.arrow, Pinceau.ENCRE, 1.2)

func belier(e: Dictionary, r: float, corps: Color) -> void:
	var lance: bool = e.state == "charge"
	var gratte: float = n.anticipation if e.state == "windup" else 0.0
	var long := 1.32 if lance else 1.12
	var large := 0.8 if lance else 0.92
	var corne := 1.25 if lance else 1.0 + 0.2 * gratte
	_sabots(r, lance, gratte)
	p.ellipse(Vector2(-0.1 * r, 0.0), r * long, r * large, corps)
	for s: float in [-1.0, 1.0]:
		var spire := PackedVector2Array()
		for i in 13:
			var u := i / 12.0
			spire.append(Vector2(0.5, 0.74 * s) * r + Vector2.from_angle((-1.9 - 4.1 * u) * s) * r * corne * lerpf(0.52, 0.36, u))
		p.ruban(spire, IVOIRE, r * 0.26)
	p.ligne(Vector2(-0.95, 0.0) * r, Vector2(0.1, 0.0) * r, corps.darkened(0.3), 2.0)
	p.ellipse(Vector2(0.72 * r, 0.0), r * 0.5, r * 0.44, corps.darkened(0.3), Pinceau.ENCRE, 2.0)
	p.yeux(Vector2(0.72 * r, 0.0), r, PAL.danger if lance or gratte > 0.0 else Color("#fff3a0"), 0.9, 0.36, 0.12)
	for s: float in [-0.16, 0.16]:
		p.disque(Vector2(1.08, s) * r, r * 0.06, Pinceau.ENCRE, Pinceau.SANS)

## Les sabots du bélier : ils trottent, grattent le sol avant la charge, se couchent pendant.
func _sabots(r: float, lance: bool, gratte: float) -> void:
	var pas: float = sin(n.marche) * 0.3 * n.allure + sin(temps * 26.0) * 0.22 * gratte
	for s: float in [-1.0, 1.0]:
		var x := -0.75 if lance else 0.25 + pas * s
		p.disque(Vector2(x, 0.86 * s) * r, r * 0.2, ORBITE, Pinceau.SANS)
		p.disque(Vector2(-0.9 if lance else -0.6 - pas * s, 0.8 * s) * r, r * 0.2, ORBITE, Pinceau.SANS)

func possede(e: Dictionary, r: float, corps: Color, g: Dictionary) -> void:
	var amorce: bool = e.state == "windup"
	var k: float = clampf(e.stateTime / maxf(1e-3, g.tuning.enemies.exploder.windup), 0.0, 1.0) if amorce else 0.0
	var peau: Color = Color.WHITE if amorce and sin(e.stateTime * 40.0) > 0.0 else corps
	p.disque(Vector2.ZERO, r, peau)
	var fissure := Color("#fff4b0") if amorce else Color("#6a1f00")
	for i in 5:
		var a: float = i * 1.257 + temps * 0.8 + e.id
		var coude: Vector2 = Vector2.from_angle(a + 0.35) * r * 0.5
		p.filet(PackedVector2Array([Vector2.from_angle(a) * r * 0.15, coude, Vector2.from_angle(a + 0.1) * r * 0.92]), fissure, 1.5 + 1.5 * k)
	for s: float in [-0.5, 0.5]:
		var oeil: Vector2 = Vector2.from_angle(s) * r * 0.5
		p.disque(oeil, r * (0.27 + 0.08 * k), Color.WHITE, Pinceau.ENCRE, 1.0)
		p.disque(oeil + Vector2(r * 0.07, 0.0), r * 0.1, Pinceau.ENCRE, Pinceau.SANS)

func pyromancienne(e: Dictionary, r: float, corps: Color) -> void:
	var incante: bool = e.state == "windup"
	var k: float = n.anticipation if incante else 0.0
	var sombre := corps.darkened(0.45)
	var traine: float = sin(n.marche) * 0.35 * n.allure + sin(temps * 3.0 + e.id) * 0.08
	p.pic(Vector2.from_angle(PI - 0.95) * r * 0.9, Vector2.from_angle(PI + 0.95) * r * 0.9, Vector2(-1.85, traine) * r, sombre, Pinceau.ENCRE, 2.5)
	var angle := lerpf(1.25, 0.3, minf(1.0, k * 3.0)) if incante else 1.25
	var bout: Vector2 = Vector2.from_angle(angle) * r * (1.95 if incante else 1.65)
	p.baton(Vector2.from_angle(angle) * r * 0.4, bout, BOIS, 2.5)
	p.disque(Vector2.ZERO, r, corps)
	p.disque(Vector2(0.22 * r, 0.0), r * 0.58, Color("#2a0810"), Pinceau.SANS)
	p.yeux(Vector2(0.22 * r, 0.0), r, PAL.gold, 0.6, 0.34, 0.12)
	flamme(bout, r * (0.44 + 0.4 * k) * (0.85 + 0.15 * sin(temps * 22.0 + e.id)))

## Flamme : halo, goutte orange dressée vers le haut de l'écran, cœur jaune.
func flamme(centre: Vector2, taille: float) -> void:
	var cote := haut.orthogonal()
	p.lueur(centre, taille * 3.0, PAL.lava, 0.6)
	p.forme(PackedVector2Array([centre + cote * taille, centre + haut * taille * 2.1, centre - cote * taille]), PAL.lava, Pinceau.SANS)
	p.disque(centre, taille, PAL.lava, Pinceau.SANS)
	p.disque(centre + haut * taille * 0.1, taille * 0.5, PAL.crit, Pinceau.SANS)

func necromancien(e: Dictionary, r: float, corps: Color) -> void:
	var canalise: bool = e.state == "channel"
	var tour: float = temps * (7.0 if canalise else 1.6) + e.id
	for i in 3:
		var a: float = tour + i * TAU / 3.0
		var c: Vector2 = Vector2.from_angle(a) * r * (1.75 if canalise else 1.5)
		p.pic(c + Vector2.from_angle(a + 2.2) * r * 0.22, c + Vector2.from_angle(a - 2.2) * r * 0.22, c + Vector2.from_angle(a) * r * 0.36,
			PAL.summon if canalise else OSSEMENT, Pinceau.ENCRE, 1.5)
	var robe := PackedVector2Array()
	var ondule: float = temps * 2.0 + n.marche
	for i in 18:
		robe.append(Vector2.from_angle(i * TAU / 18.0) * r * ((1.06 + 0.05 * sin(ondule + i * 1.7)) if i % 2 == 0 else 0.86))
	p.forme(robe, corps)
	var crane := Vector2(0.25 * r, 0.0)
	p.disque(crane, r * 0.56, OSSEMENT, Pinceau.ENCRE, 2.0)
	for s: float in [-0.8, 0.8]:
		p.disque(crane + Vector2.from_angle(s) * r * 0.3, r * 0.14, ORBITE, Pinceau.SANS)
	if canalise:
		p.yeux(crane, r, PAL.summon, 0.8, 0.3, 0.09)
		p.lueur(Vector2.ZERO, r * 2.4, PAL.summon, 0.35)
