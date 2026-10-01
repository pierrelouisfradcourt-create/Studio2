extends RefCounted
## Les 7 ARCHÉTYPES d'ennemis, une fonction par créature. Repère déjà posé : origine au centre
## de l'ennemi, x = devant lui (vers le héros), y = son côté droit. `r` = rayon dessiné,
## `corps` = sa couleur (ou celle du flash d'impact) ; les ombres du corps en sont dérivées.
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
## Le haut de l'écran, exprimé dans le repère tourné de la créature (pour les flammes).
var haut := Vector2.UP

func _init(pinceau: Pinceau) -> void:
	p = pinceau

func dessiner(e: Dictionary, r: float, face: float, corps: Color, g: Dictionary) -> void:
	haut = Vector2.UP.rotated(-face)
	match e.kind:
		"imp": diablotin(e, r, corps)
		"brute": brute(e, r, corps)
		"archer": archer(e, r, corps)
		"charger": belier(e, r, corps)
		"exploder": possede(e, r, corps, g)
		"pyromancer": pyromancienne(e, r, corps)
		"necromancer": necromancien(e, r, corps)
		_: diablotin(e, r, corps)

func diablotin(e: Dictionary, r: float, corps: Color) -> void:
	var sombre := corps.darkened(0.42)
	var bat: float = sin(temps * 9.0 + e.id) * 0.18
	var fouet: float = sin(temps * 7.0 + e.id * 1.7) * 0.3
	p.ruban(PackedVector2Array([Vector2(-0.8, 0.0) * r, Vector2(-1.3, fouet * 0.5) * r, Vector2(-1.75, fouet) * r]), sombre, r * 0.16)
	p.pic(Vector2(-1.68, fouet - 0.24) * r, Vector2(-1.68, fouet + 0.24) * r, Vector2(-2.2, fouet * 1.2) * r, sombre)
	for s: float in [-1.0, 1.0]:
		p.forme(PackedVector2Array([
			Vector2(-0.05, 0.7 * s) * r, Vector2(-0.3, (1.95 + bat) * s) * r, Vector2(-0.75, (1.35 + bat) * s) * r,
			Vector2(-1.3, (1.6 + bat) * s) * r, Vector2(-1.0, 0.4 * s) * r]), sombre, Pinceau.ENCRE, 2.0)
		p.pic(Vector2(0.3, 0.78 * s) * r, Vector2(0.78, 0.5 * s) * r, Vector2(1.25, 1.0 * s) * r, CORNE, Pinceau.ENCRE, 1.5)
	p.disque(Vector2.ZERO, r, corps)
	p.yeux(Vector2.ZERO, r, Color("#ffe14a"), 0.5, 0.52, 0.17)

func brute(e: Dictionary, r: float, corps: Color) -> void:
	var sombre := corps.darkened(0.18)
	var arme: bool = e.state == "windup"
	var ouverture := 0.85 if arme else 1.3
	var allonge := 1.15 if arme else 0.9
	for s: float in [-1.0, 1.0]:
		p.pic(Vector2(-0.75, 0.45 * s) * r, Vector2(-0.3, 0.9 * s) * r, Vector2(-0.95, 1.15 * s) * r, corps.darkened(0.4))
	for s: float in [-1.0, 1.0]:
		var poing: Vector2 = Vector2.from_angle(ouverture * s) * r * allonge
		p.disque(poing, r * 0.45, sombre, Pinceau.ENCRE, 3.0)
		p.arc(poing, r * 0.27, -0.9, 0.9, corps.darkened(0.6), 2.0)
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	p.calotte(Vector2.ZERO, r * 0.94, -1.05, 1.05, corps.darkened(0.5))
	for s: float in [-1.0, 1.0]:
		p.pic(Vector2(0.78, 0.2 * s) * r, Vector2(0.72, 0.52 * s) * r, Vector2(1.28, 0.44 * s) * r, IVOIRE, Pinceau.ENCRE, 1.5)
	p.yeux(Vector2.ZERO, r, Color("#ffb03a"), 0.36, 0.7, 0.11)

func archer(e: Dictionary, r: float, corps: Color) -> void:
	var capuche := Color("#6b4f3e")
	var tension: float = clampf(e.stateTime / 0.4, 0.0, 1.0) if e.state == "windup" else 0.0
	var pan := Pinceau.pts_arc(Vector2.ZERO, r * 1.14, 1.35, 2.75, 6)
	pan.append(Vector2(-1.8, 0.0) * r)
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
	var long := 1.32 if lance else 1.12
	var large := 0.8 if lance else 0.92
	var corne := 1.25 if lance else 1.0
	p.ellipse(Vector2(-0.1 * r, 0.0), r * long, r * large, corps)
	for s: float in [-1.0, 1.0]:
		var spire := PackedVector2Array()
		for i in 13:
			var u := i / 12.0
			spire.append(Vector2(0.5, 0.74 * s) * r + Vector2.from_angle((-1.9 - 4.1 * u) * s) * r * corne * lerpf(0.52, 0.36, u))
		p.ruban(spire, IVOIRE, r * 0.26)
	p.ligne(Vector2(-0.95, 0.0) * r, Vector2(0.1, 0.0) * r, corps.darkened(0.3), 2.0)
	p.ellipse(Vector2(0.72 * r, 0.0), r * 0.5, r * 0.44, corps.darkened(0.3), Pinceau.ENCRE, 2.0)
	p.yeux(Vector2(0.72 * r, 0.0), r, Color("#fff3a0"), 0.9, 0.36, 0.12)
	for s: float in [-0.16, 0.16]:
		p.disque(Vector2(1.08, s) * r, r * 0.06, Pinceau.ENCRE, Pinceau.SANS)

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
	var sombre := corps.darkened(0.45)
	p.pic(Vector2.from_angle(PI - 0.95) * r * 0.9, Vector2.from_angle(PI + 0.95) * r * 0.9, Vector2(-1.85, 0.0) * r, sombre, Pinceau.ENCRE, 2.5)
	var angle := 0.35 if incante else 1.25
	var bout: Vector2 = Vector2.from_angle(angle) * r * (1.95 if incante else 1.65)
	p.baton(Vector2.from_angle(angle) * r * 0.4, bout, BOIS, 2.5)
	p.disque(Vector2.ZERO, r, corps)
	p.disque(Vector2(0.22 * r, 0.0), r * 0.58, Color("#2a0810"), Pinceau.SANS)
	p.yeux(Vector2(0.22 * r, 0.0), r, PAL.gold, 0.6, 0.34, 0.12)
	_flamme(bout, r * (0.78 if incante else 0.44) * (0.85 + 0.15 * sin(temps * 22.0 + e.id)))

## Flamme : halo, goutte orange dressée vers le haut de l'écran, cœur jaune.
func _flamme(centre: Vector2, taille: float) -> void:
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
	for i in 18:
		robe.append(Vector2.from_angle(i * TAU / 18.0) * (r * 1.06 if i % 2 == 0 else r * 0.86))
	p.forme(robe, corps)
	var crane := Vector2(0.25 * r, 0.0)
	p.disque(crane, r * 0.56, OSSEMENT, Pinceau.ENCRE, 2.0)
	for s: float in [-0.8, 0.8]:
		p.disque(crane + Vector2.from_angle(s) * r * 0.3, r * 0.14, ORBITE, Pinceau.SANS)
	if canalise:
		p.yeux(crane, r, PAL.summon, 0.8, 0.3, 0.09)
		p.lueur(Vector2.ZERO, r * 2.4, PAL.summon, 0.35)
