extends "res://jeu/monde/calque.gd"
## Tout ce qui ANNONCE un danger, au sol, sous les créatures : cercles d'invocation, flaques qui
## brûlent (avec leur temps restant), zones de danger (cercle, ligne, anneau) et télégraphes des
## ennemis (cône, ligne, cercle) dont la jauge se remplit jusqu'à l'impact.
## Règle du jeu : le rouge veut dire « ça fait mal ». Une alerte inoffensive (`harmless`) est
## violette, sans remplissage. Les bords sont retracés par-dessus les créatures (contours.gd).

const LANGUES := 10
const FONDU_FLAQUE := 4.0 # la flaque pâlit dans le dernier quart de sa vie
const INVOCATION := Color("#c0304a")
const INVOCATION_LUEUR := Color("#ff2a4a")
const FLAMME := Color("#ffb03a")

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	for s in g.spawns:
		_invocation(s)
	for h in g.hazards:
		if D6Js.truthy(h.get("burning")) and not D6Js.truthy(h.get("done")) and D6Js.truthy(h.get("hitsPlayer")):
			_flaque(h)
	for h in g.hazards:
		if D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("burning")) and not D6Js.truthy(h.get("done")):
			_zone(h)
	for e in g.enemies:
		if not D6Js.truthy(e.get("dead")):
			_telegraphe(e, g)

## Cercle d'invocation : il se resserre et s'allume jusqu'à l'apparition de l'ennemi.
func _invocation(s: Dictionary) -> void:
	var t := temps()
	var k := clampf(1.0 - s.t / maxf(1e-3, s.warn), 0.0, 1.0)
	var p := Vector2(s.x, s.y)
	var r := 18.0 + 14.0 * k
	var couleur: Color = PAL.eliteArdent if D6Js.truthy(s.get("elite")) else INVOCATION
	var a := 0.4 + 0.5 * k
	Trace.halo(self, p, r * 2.0, INVOCATION_LUEUR, 0.25 * k)
	draw_circle(p, r, Color(0, 0, 0, 0.25 * a), true, -1.0, true)
	Trace.cercle_pointille(self, p, r, Trace.voile(couleur, a), 2.5, 6.0, 6.0, t * 40.0)
	draw_circle(p, r * 0.55, Trace.voile(couleur, a), false, 2.0, true)
	draw_circle(p, 1.0 + r * 0.3 * k, Trace.voile(couleur, a * 0.8), true, -1.0, true)

## Zone de danger posée dans la salle.
func _zone(h: Dictionary) -> void:
	var progression: float = D6Projectiles.hazard_progress(h)
	var p := Vector2(h.x, h.y)
	match h.shape:
		"circle":
			_cercle(p, h.r, progression)
		"ring":
			_anneau(p, h.r, h.inner, progression)
		_:
			_ligne(p, h.angle, h.length, h.width, progression)

## Télégraphe porté par un ennemi (e.tele), et canalisation de l'élite invocateur.
func _telegraphe(e: Dictionary, g: Dictionary) -> void:
	var p: Vector2 = partie.position_dessin(e)
	var t = e.get("tele")
	if t is Dictionary:
		var progression: float = float(t.get("progress", 0.0))
		if D6Js.truthy(t.get("harmless")):
			_inoffensif(p, t.r, progression)
		elif t.shape == "cone":
			_cone(p, t.angle, t["range"], t.arc, progression)
		elif t.shape == "line":
			_ligne(p, t.angle, t.length, t.width, progression)
		else:
			_cercle(p, t.r, progression)
	var invocateur = g.tuning.elite.mods.get("invocateur")
	if e.get("modPhase") == "channel" and float(e.get("modDur", 0.0)) > 0.0 and invocateur is Dictionary:
		_inoffensif(p, invocateur.channelRadius, minf(1.0, 1.0 - e.modT / e.modDur))

func _cone(p: Vector2, angle: float, portee: float, ouverture: float, progression: float) -> void:
	var a0 := angle - ouverture / 2.0
	var a1 := angle + ouverture / 2.0
	var k := clampf(progression, 0.0, 1.0)
	draw_colored_polygon(Trace.secteur(p, portee, a0, a1), PAL.dangerFill)
	if k > 0.02:
		draw_colored_polygon(Trace.secteur(p, portee * k, a0, a1), Trace.voile(PAL.dangerFillHot, PAL.dangerFillHot.a * alerte(progression)))
		draw_polyline(Trace.arc(p, portee * k, a0, a1), Trace.voile(PAL.danger, 0.55), 1.5, true)
	var bord := Trace.voile(PAL.danger, 0.45)
	draw_line(p, p + Vector2.from_angle(a0) * portee, bord, 1.5, true)
	draw_line(p, p + Vector2.from_angle(a1) * portee, bord, 1.5, true)
	draw_polyline(Trace.arc(p, portee, a0, a1), PAL.danger, 2.5, true)

func _ligne(p: Vector2, angle: float, longueur: float, largeur: float, progression: float) -> void:
	var k := clampf(progression, 0.0, 1.0)
	draw_colored_polygon(Trace.bande(p, angle, longueur, largeur), PAL.dangerFill)
	if k > 0.02:
		draw_colored_polygon(Trace.bande(p, angle, longueur * k, largeur), Trace.voile(PAL.dangerFillHot, PAL.dangerFillHot.a * alerte(progression)))
		var front := p + Vector2.from_angle(angle) * longueur * k
		var travers := Vector2.from_angle(angle).orthogonal() * largeur / 2.0
		draw_line(front - travers, front + travers, Trace.voile(PAL.danger, 0.55), 1.5, true)
	Trace.contour(self, Trace.bande(p, angle, longueur, largeur), PAL.danger, 2.0)

func _cercle(p: Vector2, r: float, progression: float) -> void:
	var k := clampf(progression, 0.0, 1.0)
	draw_circle(p, r, PAL.dangerFill, true, -1.0, true)
	if k > 0.02:
		draw_circle(p, r * k, Trace.voile(PAL.dangerFillHot, PAL.dangerFillHot.a * alerte(progression)), true, -1.0, true)
		draw_circle(p, r * k, Trace.voile(PAL.danger, 0.55), false, 1.5, true)
	draw_circle(p, r, PAL.danger, false, 2.5, true)

## Anneau : la jauge part du bord intérieur, le centre (sûr) n'est jamais peint en rouge.
func _anneau(p: Vector2, r: float, dedans: float, progression: float) -> void:
	var k := clampf(progression, 0.0, 1.0)
	var n := Trace.segments(r)
	draw_arc(p, (r + dedans) / 2.0, 0.0, TAU, n, PAL.dangerFill, r - dedans)
	if k > 0.02:
		var front := dedans + (r - dedans) * k
		draw_arc(p, (front + dedans) / 2.0, 0.0, TAU, n, Trace.voile(PAL.dangerFillHot, PAL.dangerFillHot.a * alerte(progression)), front - dedans)
		draw_circle(p, front, Trace.voile(PAL.danger, 0.55), false, 1.5, true)
	draw_circle(p, r, PAL.danger, false, 2.5, true)
	draw_circle(p, dedans, PAL.danger, false, 2.5, true)

## Alerte sans danger (invocation, chant) : violette, sans remplissage rouge.
func _inoffensif(p: Vector2, r: float, progression: float) -> void:
	var k := clampf(progression, 0.0, 1.0)
	var couleur := Trace.voile(PAL.summon, 0.35 + 0.5 * k)
	draw_circle(p, r, Trace.voile(PAL.summon, 0.05), true, -1.0, true)
	Trace.cercle_pointille(self, p, r, couleur, 2.5, 10.0, 6.0, temps() * 30.0)
	if k > 0.02:
		draw_circle(p, r * k, couleur, false, 2.5, true)

## Flaque brûlante (zone persistante allumée) : sol embrasé, langues de feu au bord, contour
## rouge, et une jauge circulaire qui se vide : le temps restant se LIT.
func _flaque(h: Dictionary) -> void:
	var t := temps()
	var reste: float = D6Projectiles.linger_left(h)
	var fondu := minf(1.0, reste * FONDU_FLAQUE)
	var p := Vector2(h.x, h.y)
	var r: float = h.r
	var phase := float(h.get("id", 0.0))
	Trace.halo(self, p, r * 1.6, PAL.lava, 0.35 * fondu)
	draw_circle(p, r, Trace.voile(PAL.lavaDim, 0.15 + 0.5 * fondu), true, -1.0, true)
	draw_circle(p, r * 0.82, Trace.voile(PAL.lava, (0.3 + 0.12 * sin(t * 9.0 + phase)) * fondu), true, -1.0, true)
	for i in LANGUES:
		_langue(p, r, i, t + phase, fondu)
	draw_circle(p, r, PAL.danger, false, 2.5, true)
	if reste > 0.005:
		draw_arc(p, r + 6.0, -PI / 2.0, -PI / 2.0 + reste * TAU, Trace.segments(r, reste * TAU), Trace.CERNE, 5.5, true)
		draw_arc(p, r + 6.0, -PI / 2.0, -PI / 2.0 + reste * TAU, Trace.segments(r, reste * TAU), PAL.impactRing, 3.0, true)

## Langue de feu qui monte de la flaque : la zone « vit ».
func _langue(p: Vector2, r: float, i: int, t: float, fondu: float) -> void:
	var a := float(i) / float(LANGUES) * TAU + t * 0.6
	var pied := p + Vector2.from_angle(a) * r * (0.86 if i % 2 == 0 else 0.45)
	var h := r * (0.3 + 0.1 * sin(t * 14.0 + float(i) * 1.7))
	var d := 3.0 * sin(t * 9.0 + float(i))
	var flamme := PackedVector2Array([
		pied + Vector2(-6, 0), pied + Vector2(-6.5, -h * 0.3), pied + Vector2(d * 0.5 - 3.5, -h * 0.7), pied + Vector2(d, -h),
		pied + Vector2(d * 0.5 + 2.0, -h * 0.65), pied + Vector2(6.5, -h * 0.3), pied + Vector2(6, 0),
	])
	draw_colored_polygon(flamme, Trace.voile(FLAMME, 0.85 * fondu))
	var coeur := PackedVector2Array([pied + Vector2(-3, 0), pied + Vector2(d * 0.3, -h * 0.5), pied + Vector2(3, 0)])
	draw_colored_polygon(coeur, Trace.voile(Color("#fff0c0"), 0.8 * fondu))
