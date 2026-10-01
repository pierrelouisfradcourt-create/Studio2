extends "res://jeu/monde/calque.gd"
## Tout ce qui ANNONCE un danger, au sol, sous les créatures : cercles d'invocation, flaques qui
## brûlent, zones de danger (cercle, ligne, anneau) et télégraphes des ennemis (cône, ligne,
## cercle).
## Lecture d'une zone : un remplissage LÉGER (on voit toujours le héros et les ennemis dedans),
## une JAUGE qui avance de l'intérieur vers le bord — quand son front clair touche le contour,
## ça frappe — et un ÉCLAT à l'instant de la frappe. Le contour net, lui, est tracé par-dessus
## les créatures (contours.gd).
## Règle du jeu : le rouge veut dire « ça fait mal ». Une alerte inoffensive (`harmless`) est
## violette, sans jauge rouge.

const LEGER := 0.075 # opacité du remplissage d'une zone
const JAUGE := 0.6 # opacité de la jauge à son front, en fin de course
const FRONT := Color("#ffe6cc") # le front de la jauge : clair, presque blanc
const BRAISE := Color(1.0, 0.33, 0.18)
const ECLAT_VIE := 0.24 # s
const ECLAT_SEUIL := 0.85 # un télégraphe qui disparaît au-delà a frappé (en deçà : annulé)
const LANGUES := 9
const FONDU_FLAQUE := 4.0 # la flaque pâlit dans le dernier quart de sa vie
const INVOCATION := Color("#c0304a")
const INVOCATION_LUEUR := Color("#ff2a4a")
const FLAMME := Color("#ffb03a")

## Éclats en cours : [{forme: Dictionary (shape, p, r, inner, angle, length, width, arc), vie: float}].
var _eclats: Array = []
## Zones hostiles vues à la dernière image : id -> zone (pour reconnaître celle qui frappe).
var _zones := {}
## Télégraphes portés vus à la dernière image : id d'ennemi -> {forme, k}.
var _teles := {}

func relier(p_monde: Node2D, p_partie: Node) -> void:
	super.relier(p_monde, p_partie)
	partie.evenements.connect(_sur_evenements)
	partie.partie_demarree.connect(_oublier)

func _oublier() -> void:
	_eclats.clear()
	_zones.clear()
	_teles.clear()

## Une zone hostile vient de frapper : son éclat.
func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		if ev.get("type") == "hazardFire" and _zones.has(ev.get("id")):
			var h: Dictionary = _zones[ev.id]
			_eclats.append({"forme": _forme_de(Vector2(h.x, h.y), h), "vie": ECLAT_VIE})

func _forme_de(p: Vector2, d: Dictionary) -> Dictionary:
	var genre = d.get("shape", "circle")
	return {
		"shape": genre, "p": p, "r": _nombre(d, "range") if genre == "cone" else _nombre(d, "r"),
		"inner": _nombre(d, "inner"), "angle": _nombre(d, "angle"), "length": _nombre(d, "length"),
		"width": _nombre(d, "width"), "arc": _nombre(d, "arc"),
	}

## Nombre lu dans un champ que la simulation ne pose pas toujours.
static func _nombre(d: Dictionary, cle: String) -> float:
	var v = d.get(cle)
	return float(v) if v is float or v is int else 0.0

func _process(delta: float) -> void:
	var g = etat()
	if g != null and not partie.en_pause:
		_suivre(g, delta)
	redessiner()

## Mémoire de présentation : quelles zones et quels télégraphes étaient là, pour savoir lesquels
## viennent de frapper. Ne touche pas à la partie.
func _suivre(g: Dictionary, delta: float) -> void:
	for e in _eclats:
		e.vie -= delta
	_eclats = _eclats.filter(func(e): return e.vie > 0.0)
	_zones.clear()
	for h in g.hazards:
		if D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("burning")) and not D6Js.truthy(h.get("done")):
			_zones[h.id] = h
	var avant := _teles
	_teles = {}
	var actifs := {}
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or _nombre(e, "stun") > 0.0:
			continue
		actifs[e.id] = true
		var t = e.get("tele")
		if not (t is Dictionary) or D6Js.truthy(t.get("harmless")):
			continue
		var k := _nombre(t, "progress")
		var forme := _forme_de(partie.position_dessin(e), t)
		# Une attaque qui se répète (vagues d'un Gardien) : la jauge retombe d'un coup.
		if avant.has(e.id) and avant[e.id].k >= ECLAT_SEUIL and k < avant[e.id].k - 0.5:
			_eclats.append({"forme": avant[e.id].forme, "vie": ECLAT_VIE})
		_teles[e.id] = {"forme": forme, "k": k}
	for id in avant:
		if not _teles.has(id) and actifs.has(id) and avant[id].k >= ECLAT_SEUIL:
			_eclats.append({"forme": avant[id].forme, "vie": ECLAT_VIE})

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	_invocations(g.spawns)
	_flaques(g.hazards.filter(func(h): return D6Js.truthy(h.get("burning")) and not D6Js.truthy(h.get("done")) and D6Js.truthy(h.get("hitsPlayer"))))
	var zones := _zones_hostiles(g)
	var fronts := Trace.Lot.new()
	# Trois passes (remplissages, jauges, fronts) : les zones de même nature partent en lot.
	for z in zones:
		_fond(z.f)
	for z in zones:
		_jauge(z.f, z.k, fronts)
	fronts.tracer(self, 2.0)
	_inoffensifs(g)
	for e in _eclats:
		_eclat(e.forme, e.vie / ECLAT_VIE)

## Les zones qui vont frapper le héros : [{f: forme, k: progression 0..1}] (zones posées dans la
## salle et télégraphes portés par les ennemis).
func _zones_hostiles(g: Dictionary) -> Array:
	var zones: Array = []
	for h in g.hazards:
		if D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("burning")) and not D6Js.truthy(h.get("done")):
			zones.append({"f": _forme_de(Vector2(h.x, h.y), h), "k": D6Projectiles.hazard_progress(h)})
	for e in g.enemies:
		var t = e.get("tele")
		if t is Dictionary and not D6Js.truthy(e.get("dead")) and not D6Js.truthy(t.get("harmless")):
			zones.append({"f": _forme_de(partie.position_dessin(e), t), "k": clampf(_nombre(t, "progress"), 0.0, 1.0)})
	return zones

## Remplissage LÉGER d'une zone : on voit toujours ce qui se tient dedans.
func _fond(f: Dictionary) -> void:
	var fond := Trace.voile(PAL.danger, LEGER)
	match f.shape:
		"cone":
			draw_colored_polygon(Trace.secteur(f.p, f.r, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0), fond)
		"line":
			draw_primitive(Trace.bande(f.p, f.angle, f.length, f.width), PackedColorArray([fond, fond, fond, fond]), PackedVector2Array())
		"ring":
			draw_arc(f.p, (f.r + f.inner) / 2.0, 0.0, TAU, Trace.segments(f.r), fond, f.r - f.inner)
		_:
			Trace.plein(self, f.p, f.r, fond)

## La jauge : elle avance de l'intérieur vers le bord, dense à son front. Le front lui-même
## (un trait clair) part dans le lot des fronts.
func _jauge(f: Dictionary, k: float, fronts: Trace.Lot) -> void:
	if k <= 0.02:
		return
	var jauge := Trace.voile(BRAISE, JAUGE * (0.45 + 0.55 * k) * alerte(k))
	var front := BRAISE.lerp(FRONT, 0.55 + 0.45 * k) # opaque : les segments du lot se recouvrent sans perler
	match f.shape:
		"cone":
			_jauge_cone(f, k, jauge)
			fronts.arc(f.p, f.r * k, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0, front)
		"line":
			var pts := Trace.bande(f.p, f.angle, f.length * k, f.width)
			var pale := Trace.voile(jauge, jauge.a * 0.12)
			draw_primitive(pts, PackedColorArray([pale, jauge, jauge, pale]), PackedVector2Array())
			fronts.segment(pts[1], pts[2], front)
		"ring":
			var bord: float = f.inner + (f.r - f.inner) * k
			var epais := minf(bord - f.inner, 26.0)
			var n := Trace.segments(f.r)
			draw_arc(f.p, bord - epais / 2.0, 0.0, TAU, n, Trace.voile(jauge, jauge.a * 0.45), epais)
			draw_arc(f.p, bord - epais / 6.0, 0.0, TAU, n, Trace.voile(jauge, jauge.a * 0.5), epais / 3.0)
			fronts.cercle(f.p, bord, front)
		_:
			Trace.jauge(self, f.p, f.r * k, jauge)
			fronts.cercle(f.p, f.r * k, front)

func _jauge_cone(f: Dictionary, k: float, jauge: Color) -> void:
	var pts := Trace.secteur(f.p, f.r * k, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0)
	var uvs := PackedVector2Array()
	for pt in pts:
		uvs.append(Vector2(0.5, 0.5) + (pt - f.p) / (2.0 * f.r * k))
	draw_colored_polygon(pts, jauge, uvs, Trace.texture_jauge())

## L'instant de la frappe : la zone s'embrase d'un coup puis s'éteint (0,24 s).
func _eclat(f: Dictionary, reste: float) -> void:
	var blanc := Trace.voile(FRONT, 0.62 * reste * reste)
	var bord := Trace.voile(Color.WHITE, reste)
	var pousse := 1.0 + 0.06 * (1.0 - reste)
	match f.shape:
		"cone":
			var pts := Trace.secteur(f.p, f.r * pousse, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0)
			Trace.forme(self, pts, blanc, bord, 3.0)
		"line":
			Trace.forme(self, Trace.bande(f.p, f.angle, f.length, f.width * pousse), blanc, bord, 3.0)
		"ring":
			draw_arc(f.p, (f.r + f.inner) / 2.0, 0.0, TAU, Trace.segments(f.r), blanc, f.r - f.inner)
			draw_circle(f.p, f.r * pousse, bord, false, 3.0, true)
		_:
			Trace.plein(self, f.p, f.r, blanc)
			draw_circle(f.p, f.r * pousse, bord, false, 3.0, true)

## Alertes sans danger (invocation, chant, canalisation d'un élite invocateur) : violettes,
## pointillées, sans remplissage rouge. Toutes en un lot.
func _inoffensifs(g: Dictionary) -> void:
	var lot := Trace.Lot.new()
	var invocateur = g.tuning.elite.mods.get("invocateur")
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var p: Vector2 = partie.position_dessin(e)
		var t = e.get("tele")
		if t is Dictionary and D6Js.truthy(t.get("harmless")):
			_inoffensif(lot, p, t.r, _nombre(t, "progress"))
		if e.get("modPhase") == "channel" and _nombre(e, "modDur") > 0.0 and invocateur is Dictionary:
			_inoffensif(lot, p, invocateur.channelRadius, minf(1.0, 1.0 - e.modT / e.modDur))
	lot.tracer(self, 2.5)

func _inoffensif(lot: Trace.Lot, p: Vector2, r: float, progression: float) -> void:
	var k := clampf(progression, 0.0, 1.0)
	var couleur := Trace.voile(PAL.summon, 0.4 + 0.5 * k)
	Trace.plein(self, p, r, Trace.voile(PAL.summon, 0.045))
	lot.pointille(p, r, couleur, 10.0, 6.0, temps() * 30.0)
	if k > 0.02:
		lot.cercle(p, r * k, couleur)

## Cercles d'invocation : ils se resserrent et s'allument jusqu'à l'apparition de l'ennemi.
## Les lueurs d'abord, puis tous les traits en un lot.
func _invocations(apparitions: Array) -> void:
	var lot := Trace.Lot.new()
	for s in apparitions:
		var k := clampf(1.0 - s.t / maxf(1e-3, s.warn), 0.0, 1.0)
		var p := Vector2(s.x, s.y)
		var r := 18.0 + 14.0 * k
		var a := 0.4 + 0.5 * k
		var couleur: Color = Trace.voile(PAL.eliteArdent if D6Js.truthy(s.get("elite")) else INVOCATION, a)
		Trace.halo(self, p, r * 1.4, Color.BLACK, 0.45 * a)
		Trace.halo(self, p, r * 2.2, INVOCATION_LUEUR, 0.3 * k)
		Trace.halo(self, p, 3.0 + r * 0.6 * k, couleur, 0.9)
		lot.pointille(p, r, couleur, 6.0, 6.0, temps() * 40.0)
		lot.cercle(p, r * 0.55, couleur)
	lot.tracer(self, 2.5)

## Flaques brûlantes (zones persistantes allumées) : sol embrasé LÉGER, langues de feu sur le
## bord. Contour et temps restant sont tracés par-dessus les créatures (contours.gd).
func _flaques(flaques: Array) -> void:
	var t := temps()
	for h in flaques:
		Trace.plein(self, Vector2(h.x, h.y), h.r, Trace.voile(PAL.lavaDim, 0.3 * _fondu(h)))
	for h in flaques:
		Trace.halo(self, Vector2(h.x, h.y), h.r * 1.05, PAL.lava, (0.3 + 0.08 * sin(t * 9.0 + _nombre(h, "id"))) * _fondu(h))
	for h in flaques:
		for i in LANGUES:
			_langue(Vector2(h.x, h.y), h.r, i, t + _nombre(h, "id"), _fondu(h))

func _fondu(h: Dictionary) -> float:
	return minf(1.0, D6Projectiles.linger_left(h) * FONDU_FLAQUE)

## Langue de feu qui monte du bord de la flaque (deux triangles, en lot) : la zone « vit ».
func _langue(p: Vector2, r: float, i: int, t: float, fondu: float) -> void:
	var a := float(i) / float(LANGUES) * TAU + t * 0.6
	var pied := p + Vector2.from_angle(a) * r * (0.9 if i % 3 != 0 else 0.5)
	var h := r * (0.26 + 0.1 * sin(t * 14.0 + float(i) * 1.7))
	var d := 3.0 * sin(t * 9.0 + float(i))
	var feu := Trace.voile(FLAMME, 0.8 * fondu)
	Trace.triangle(self, pied + Vector2(-6, 0), pied + Vector2(6, 0), pied + Vector2(d, -h), feu, feu, Trace.voile(PAL.lava, 0.0))
	var coeur := Trace.voile(Color("#fff0c0"), 0.75 * fondu)
	Trace.triangle(self, pied + Vector2(-2.5, 0), pied + Vector2(2.5, 0), pied + Vector2(d * 0.3, -h * 0.5), coeur, coeur, Trace.voile(FLAMME, 0.0))
