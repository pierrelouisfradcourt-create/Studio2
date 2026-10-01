extends "res://jeu/monde/calque.gd"
## Les bords seuls des dangers, tracés AU-DESSUS du héros et des ennemis : dans une mêlée, la
## limite d'une frappe reste lisible sans rien cacher (ce ne sont que des traits). Dans le
## dernier quart du télégraphe le trait s'épaissit et se double d'un filet clair qui bat :
## « ça part ». Une flaque qui brûle y montre son temps restant : l'arc clair se vide autour
## d'elle. Seulement ce qui fait mal (rouge) ; les alertes inoffensives restent au sol.
## Tous les traits d'une même largeur partent en un seul appel de dessin (Trace.Lot).

const LARGEUR := 2.5
const LARGEUR_PRESSEE := 4.0
const URGENCE := 0.75 # part du télégraphe à partir de laquelle le bord s'épaissit
const FILET := Color("#ffe6cc")
const ETEINT := 0.5 # assombrissement du bord d'une flaque là où le temps est déjà écoulé

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var lots := {"cerne": Trace.Lot.new(), "calme": Trace.Lot.new(), "presse": Trace.Lot.new(), "filet": Trace.Lot.new()}
	var tetes: Array[Vector2] = []
	for h in g.hazards:
		if not D6Js.truthy(h.get("hitsPlayer")) or D6Js.truthy(h.get("done")):
			continue
		if D6Js.truthy(h.get("burning")):
			tetes.append(_flaque(h, lots))
		else:
			_bord(Vector2(h.x, h.y), h, D6Projectiles.hazard_progress(h), lots)
	for e in g.enemies:
		var t = e.get("tele")
		if t is Dictionary and not D6Js.truthy(e.get("dead")) and not D6Js.truthy(t.get("harmless")):
			_bord(partie.position_dessin(e), t, float(t.get("progress", 0.0)), lots)
	lots.cerne.tracer(self, 6.5)
	lots.calme.tracer(self, LARGEUR)
	lots.presse.tracer(self, LARGEUR_PRESSEE)
	lots.filet.tracer(self, 1.2)
	for p in tetes:
		Trace.plein(self, p, 4.5, PAL.impactRing)

## Le bord d'une zone (cercle, anneau, ligne, cône), épaissi quand la frappe est imminente.
func _bord(p: Vector2, d: Dictionary, progression: float, lots: Dictionary) -> void:
	var presse := progression >= URGENCE
	var lot: Trace.Lot = lots.presse if presse else lots.calme
	var filet := PAL.danger.lerp(FILET, 0.55 + 0.45 * sin(temps() * 38.0))
	match d.get("shape", "circle"):
		"cone":
			var secteur := Trace.secteur(p, d["range"], d.angle - d.arc / 2.0, d.angle + d.arc / 2.0)
			lot.polyligne(secteur, PAL.danger, true)
			if presse:
				lots.filet.polyligne(secteur, filet, true)
		"line":
			var bande := Trace.bande(p, d.angle, d.length, d.width)
			lot.polyligne(bande, PAL.danger, true)
			if presse:
				lots.filet.polyligne(bande, filet, true)
		_:
			lot.cercle(p, d.r, PAL.danger)
			if presse:
				lots.filet.cercle(p, d.r, filet)
			if d.get("shape") == "ring" and float(d.get("inner", 0.0)) > 0.0:
				lots.calme.cercle(p, d.inner, PAL.danger)

## Flaque qui brûle : bord rouge estompé, et l'arc de son temps restant (cerné, tête claire)
## qui se vide dans le sens des aiguilles d'une montre. Renvoie la position de la tête de l'arc.
func _flaque(h: Dictionary, lots: Dictionary) -> Vector2:
	var reste: float = D6Projectiles.linger_left(h)
	var p := Vector2(h.x, h.y)
	var r: float = h.r
	var a0 := -PI / 2.0
	var a1 := a0 + reste * TAU
	lots.calme.cercle(p, r, PAL.danger.darkened(ETEINT))
	if reste > 0.005:
		lots.cerne.arc(p, r, a0, a1, Trace.CERNE)
		lots.presse.arc(p, r, a0, a1, PAL.danger.lerp(PAL.impactRing, 0.55))
	return p + Vector2.from_angle(a1) * r
