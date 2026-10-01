extends RefCounted
## Les 4 GARDIENS, une fonction par modèle. Même repère que les archétypes (x = devant lui).
##   Charon    le Passeur : couronne de pointes dorées, capuche, sa RAME
##   Cerbère   trois têtes en éventail, crinière en pointes ; en l'air pendant un bond
##   Minos     mitre dorée, robe indigo, queue de serpent ; en filigrane quand il se dissout
##   Éphialte  bloc de pierre fissuré, deux poings, chaînes (qui brillent sous bouclier)
## Commun : les yeux et les parures rougissent avec la PHASE ; un POINT FAIBLE doré pulse quand le
## Gardien est exposé (e.exposed), là où frapper.

const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL
const BRAISE := Color("#ff6a1a")
const ROCHE: Array[float] = [1.0, 0.93, 1.04, 0.96, 1.02, 0.9, 1.05, 0.95, 1.0, 0.92, 1.03, 0.97]
const TETES: Array[float] = [-0.95, 0.95, 0.0] # celle du milieu en dernier : elle passe devant

var p: Pinceau
var temps := 0.0
var _face := 0.0

func _init(pinceau: Pinceau) -> void:
	p = pinceau

func dessiner(e: Dictionary, r: float, face: float, corps: Color) -> void:
	_face = face
	match e.kind:
		"cerbere": cerbere(e, r, corps)
		"minos": minos(e, r, corps)
		"colosse": colosse(e, r, corps)
		_: charon(e, r, corps)

## Un point donné « à l'écran » (y vers le bas), dans le repère tourné du Gardien.
func _ecran(v: Vector2) -> Vector2:
	return v.rotated(-_face)

static func _expose(e: Dictionary) -> bool:
	var v = e.get("exposed")
	return (v is float or v is int) and v > 0.0

static func _alerte(e: Dictionary):
	var tele = e.get("tele")
	return tele if tele is Dictionary else {}

## Point faible exposé : halo, anneau doré qui pulse, cœur clair.
func point_faible(centre: Vector2, taille: float) -> void:
	var k := 0.5 + 0.5 * sin(temps * 14.0)
	p.lueur(centre, taille * (2.6 + 0.6 * k), PAL.gold, 0.55 + 0.35 * k)
	p.anneau(centre, taille * (1.0 + 0.12 * k), PAL.gold, 3.0)
	p.disque(centre, taille * 0.38, Color("#fff4c0"), Pinceau.SANS)

# ---------------------------------------------------------------- Charon

func charon(e: Dictionary, r: float, corps: Color) -> void:
	var parure: Color = BRAISE if e.phase >= 3.0 else PAL.bossTrim
	for i in 5:
		var a: float = PI + (i - 2) * 0.42
		var onde: float = 1.3 + 0.07 * sin(temps * 5.0 + i * 1.9)
		p.pic(Vector2.from_angle(a - 0.24) * r * 0.92, Vector2.from_angle(a + 0.24) * r * 0.92, Vector2.from_angle(a) * r * onde, corps.darkened(0.15), Pinceau.ENCRE, 2.5)
	for i in 9:
		var a: float = i * TAU / 9.0 + temps * 0.3 - _face
		p.pic(Vector2.from_angle(a - 0.19) * r * 0.97, Vector2.from_angle(a + 0.19) * r * 0.97, Vector2.from_angle(a) * r * 1.36, parure, Pinceau.ENCRE, 2.5)
	_rame(e, r)
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	p.disque(Vector2(0.12 * r, 0.0), r * 0.62, Color("#2a0610"), parure.darkened(0.25), 2.0)
	p.yeux(Vector2(0.12 * r, 0.0), r, Color("#ff3a1a") if e.phase >= 2.0 else PAL.bossTrim, 0.5, 0.36, 0.11)
	if _expose(e):
		point_faible(Vector2(-0.45 * r, 0.0), r * 0.26)

## La rame du Passeur : en travers au repos, pointée comme un bélier quand il charge.
func _rame(e: Dictionary, r: float) -> void:
	var charge: bool = e.state == "charge"
	var talon: Vector2 = Vector2(-0.5, 0.75) * r if charge else Vector2(-1.25, 0.98) * r
	var pale: Vector2 = Vector2(1.95, 0.4) * r if charge else Vector2(1.35, 1.12) * r
	var axe := (pale - talon).normalized()
	var cote := axe.orthogonal()
	p.baton(talon, pale, Color("#8a6a4a"), r * 0.11)
	p.forme(PackedVector2Array([
		pale - axe * r * 0.1 + cote * r * 0.1, pale + axe * r * 0.35 + cote * r * 0.27, pale + axe * r * 0.95 + cote * r * 0.2,
		pale + axe * r * 1.05, pale + axe * r * 0.95 - cote * r * 0.2, pale + axe * r * 0.35 - cote * r * 0.27,
		pale - axe * r * 0.1 - cote * r * 0.1]), Color("#b89868"), Pinceau.ENCRE, 2.5)
	p.disque(talon.lerp(pale, 0.52), r * 0.2, Color("#4a0e1c"), Pinceau.ENCRE, 2.0)

# ---------------------------------------------------------------- Cerbère

func cerbere(e: Dictionary, r: float, corps: Color) -> void:
	var furie: bool = e.phase >= 3.0
	var poil: Color = BRAISE if furie else corps.darkened(0.55)
	if furie:
		p.lueur(Vector2.ZERO, r * 2.2, BRAISE, 0.45 + 0.2 * sin(temps * 18.0))
	var fouet: float = sin(temps * 6.0) * 0.35
	p.ruban(PackedVector2Array([Vector2(-0.9, 0.0) * r, Vector2(-1.4, fouet * 0.35) * r, Vector2(-1.8, fouet) * r, Vector2(-2.05, fouet * 1.9) * r]), poil, r * 0.09)
	for i in 7:
		var a: float = PI + (i - 3) * 0.32
		var pointe: float = 1.28 + 0.08 * sin(temps * 9.0 + i)
		p.pic(Vector2.from_angle(a - 0.16) * r * 0.9, Vector2.from_angle(a + 0.16) * r * 0.9, Vector2.from_angle(a) * r * pointe, poil)
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	var mord: bool = _alerte(e).get("shape") == "cone"
	for ecart in TETES:
		_tete_cerbere(r, ecart * (0.8 if mord else 1.0), ecart == 0.0, corps, poil, mord, furie)
	if _expose(e):
		point_faible(Vector2(-0.38 * r, 0.0), r * 0.3)

## Une tête : oreilles pointues, museau, yeux ; celle du milieu ouvre une gueule rouge quand elle mord.
func _tete_cerbere(r: float, a: float, milieu: bool, corps: Color, poil: Color, mord: bool, furie: bool) -> void:
	var dir := Vector2.from_angle(a)
	var centre := dir * r * (1.02 if milieu else 0.95)
	var hr := r * (0.5 if milieu else 0.42)
	for s: float in [-1.0, 1.0]:
		p.pic(centre + Vector2.from_angle(a + 1.25 * s) * hr * 0.85, centre + Vector2.from_angle(a + 2.1 * s) * hr * 0.85,
			centre + Vector2.from_angle(a + 2.0 * s) * hr * 1.65, poil, Pinceau.ENCRE, 1.5)
	p.disque(centre, hr, corps, Pinceau.ENCRE, 2.5)
	var museau := centre + dir * hr * 0.75
	p.ellipse(museau, hr * 0.62, hr * 0.46, corps.lightened(0.14), Pinceau.ENCRE, 2.0, a)
	if mord and milieu:
		p.ellipse(museau + dir * hr * 0.12, hr * 0.5, hr * 0.34, PAL.danger, Pinceau.ENCRE, 1.5, a)
		for s: float in [-1.0, 1.0]:
			var croc := museau + dir * hr * 0.35 + dir.orthogonal() * hr * 0.26 * s
			p.pic(croc - dir * hr * 0.14, croc + dir * hr * 0.14, croc - dir.orthogonal() * hr * 0.3 * s, Color("#f0e0c0"), Pinceau.SANS)
	else:
		p.disque(museau + dir * hr * 0.5, hr * 0.14, Pinceau.ENCRE, Pinceau.SANS)
	p.yeux(centre, hr, Color("#ff3a1a") if furie else Color("#ffb03a"), 0.75, 0.52, 0.17, a)

# ---------------------------------------------------------------- Minos

func minos(e: Dictionary, r: float, corps: Color) -> void:
	_queue_minos(e, r)
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	p.anneau(Vector2.ZERO, r * 0.82, corps.lightened(0.18), 2.0)
	var visage := Vector2(0.12 * r, 0.0)
	p.disque(visage, r * 0.62, Color("#160f2e"), Pinceau.SANS)
	p.yeux(visage, r * 0.62, Color("#ff5a4a") if e.phase >= 3.0 else Color("#f3f0ff"), 0.45, 0.5, 0.16)
	_mitre_minos(e, r)
	if _expose(e):
		point_faible(_ecran(Vector2(0.0, 0.38 * r)), r * 0.28)

## Queue de serpent enroulée autour de lui : elle enfle et accélère quand le fouet se prépare.
func _queue_minos(e: Dictionary, r: float) -> void:
	var alerte: Dictionary = _alerte(e)
	var fouet: bool = D6Js.truthy(alerte.get("area"))
	var enfle: float = 1.0 + 0.25 * float(D6Js.nz(alerte.get("progress"), 0.0)) if fouet else 1.0
	var pts := PackedVector2Array()
	for i in 41:
		var u := i / 40.0
		var a: float = temps * (6.0 if fouet else 1.2) + u * 1.6 * TAU
		pts.append(Vector2.from_angle(a) * r * (1.08 + 0.36 * u) * enfle)
	p.ruban(pts, Color("#2f6b3c"), 7.0 if fouet else 5.0)
	p.filet(pts, Color("#8fd89a"), 1.5)
	var bout := (pts[40] - pts[39]).normalized()
	p.pic(pts[40] + bout.orthogonal() * 4.0, pts[40] - bout.orthogonal() * 4.0, pts[40] + bout * 12.0, Color("#2f6b3c"), Pinceau.ENCRE, 1.5)

## Mitre dorée, toujours dressée vers le haut de l'écran : on reconnaît le Juge à sa coiffe.
func _mitre_minos(e: Dictionary, r: float) -> void:
	var mitre := PackedVector2Array()
	for v: Vector2 in [Vector2(-0.46, -0.52), Vector2(-0.32, -1.48), Vector2(0.0, -1.06), Vector2(0.32, -1.48), Vector2(0.46, -0.52)]:
		mitre.append(_ecran(v * r))
	p.forme(mitre, PAL.bossTrim, Pinceau.ENCRE, 2.5)
	var gemme := _ecran(Vector2(0.0, -0.82 * r))
	if e.phase >= 2.0:
		p.lueur(gemme, r * (0.5 if e.phase < 3.0 else 0.8), PAL.danger, 0.8)
	p.disque(gemme, r * 0.11, PAL.danger, Pinceau.ENCRE, 1.5)

# ---------------------------------------------------------------- Éphialte, le Colosse

func colosse(e: Dictionary, r: float, corps: Color) -> void:
	var expose := _expose(e)
	var enchaine: bool = D6Js.truthy(e.get("shielded"))
	_poings_colosse(e, r, corps, enchaine)
	var bloc := PackedVector2Array()
	for i in ROCHE.size():
		bloc.append(_ecran(Vector2.from_angle(i * TAU / ROCHE.size()) * r * ROCHE[i]))
	p.forme(bloc, corps, Pinceau.ENCRE, 3.5)
	var lave: Color = Color("#ff8a2a") if expose else (Color("#c2401a") if e.phase >= 3.0 else (Color("#7a2a14") if e.phase >= 2.0 else Color("#2a201c")))
	var ep := 3.0 if expose else 2.0
	p.filet(PackedVector2Array([_ecran(Vector2(-0.5, -0.2) * r), _ecran(Vector2(-0.1, 0.05) * r), _ecran(Vector2(0.15, -0.35) * r)]), lave, ep)
	p.filet(PackedVector2Array([_ecran(Vector2(-0.1, 0.05) * r), _ecran(Vector2(0.05, 0.5) * r)]), lave, ep)
	p.filet(PackedVector2Array([_ecran(Vector2(0.45, 0.1) * r), _ecran(Vector2(0.62, 0.42) * r), _ecran(Vector2(0.4, 0.62) * r)]), lave, ep)
	_chaines_colosse(r, enchaine)
	for s: float in [-0.36, 0.36]:
		p.disque(Vector2.from_angle(s) * r * 0.56, r * 0.15, Color("#2a201c"), Pinceau.SANS)
	p.arc(Vector2.ZERO, r * 0.74, -0.62, 0.62, Color("#2a201c"), 4.0)
	p.yeux(Vector2.ZERO, r, Color("#ff8a2a") if expose else PAL.crit, 0.36, 0.56, 0.075)
	if expose:
		point_faible(_ecran(Vector2(-0.1, 0.05) * r), r * 0.24)

## Poings : levés quand il arme, l'un planté au sol quand son bras est coincé. Menottes de fer.
func _poings_colosse(e: Dictionary, r: float, corps: Color, enchaine: bool) -> void:
	var frappe: bool = e.state == "poing"
	var coince: bool = frappe and e.get("sub") == "recover"
	var leve: bool = frappe and not coince
	for s: float in [-1.0, 1.0]:
		var allonge := 1.55 if coince and s > 0.0 else (1.0 if leve else 1.18)
		var c: Vector2 = Vector2.from_angle(s * (1.25 if leve else 0.95)) * r * allonge
		p.disque(c, r * 0.42, corps.lightened(0.08), Pinceau.ENCRE, 3.0)
		p.anneau(c, r * 0.29, PAL.summon if enchaine else Color("#3a3438"), 4.0)

## Chaînes à la taille : maillons ternes ; violets et dorés, en rotation, tant que les geôliers vivent.
func _chaines_colosse(r: float, enchaine: bool) -> void:
	for i in 14:
		var a: float = i * TAU / 14.0 + (temps * 0.8 if enchaine else 0.0)
		var teinte: Color = (PAL.gold if i % 2 == 1 else PAL.summon) if enchaine else Color("#7c7479")
		var maillon := Pinceau.pts_ellipse(Vector2.from_angle(a) * r * 1.1, r * 0.11, r * 0.06, a + PI * 0.5, 10)
		maillon.append(maillon[0])
		p.filet(maillon, Pinceau.ENCRE, 5.0)
		p.filet(maillon, teinte, 2.5)
	if enchaine:
		p.lueur(Vector2.ZERO, r * 2.1, PAL.summon, 0.35 + 0.2 * sin(temps * 6.0))
		p.anneau(Vector2.ZERO, r * 1.28, Color(PAL.summon, 0.5 + 0.25 * sin(temps * 6.0)), 5.0)
