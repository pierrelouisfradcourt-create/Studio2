extends RefCounted
## Le tactile multi-doigts : joystick flottant dans la moitié gauche, boutons à la Brawl Stars à
## droite. Portage fidèle de GAMES/dungeon_666/src/input/input.mjs (layout, buttonAt,
## onPointerDown / Move / Up, updateStick, touchUI). Ne dessine rien, ne connaît pas la partie.
##
## Les longueurs sont en « px CSS » dans la version web : ici elles sont multipliées par
## `echelle` (unités du viewport par px CSS) pour garder la même taille sous le pouce.

const RAYON_MANCHE := 58.0 # course du joystick de déplacement
const MANCHE_MORT := 0.12 # fraction du rayon ignorée
const MANCHE_PLEIN := 0.7 # fraction du rayon où la vitesse est maximale (nervosité)
const VISEE_GLISSER_MIN := 18.0 # en deçà, un relâcher = tap (visée assistée)
const VISEE_ANNULER := 12.0 # après une visée manuelle, revenir au centre ANNULE la compétence
const ZONE_DEPLACEMENT := 0.48 # moitié gauche (fraction de la largeur) réservée au déplacement
const TOLERANCE_POUCE := 1.35 # zone de toucher = rayon dessiné × 1,35
const ECART_ZONE := 8.0 # entre la zone joystick et la zone de toucher du bouton le plus à gauche
const MARGE_DESSIN := 12.0 # le DESSIN du joystick reste à cette distance des bords
const AUCUN := -1 # aucun doigt

## Disposition autour du bouton d'attaque (angles en degrés, y vers le bas). Le dash est le plus
## gros et le plus proche du pouce : c'est le geste le plus important.
const BOUTONS := [
	{"id": "attack", "rayon": 48.0, "angle": 0.0, "dist": 0.0, "visee": true},
	{"id": "dash", "rayon": 40.0, "angle": 186.0, "dist": 112.0, "visee": false},
	{"id": "skill", "rayon": 33.0, "angle": 228.0, "dist": 112.0, "visee": true},
	{"id": "super", "rayon": 35.0, "angle": 268.0, "dist": 116.0, "visee": false},
	{"id": "gadget", "rayon": 27.0, "angle": 318.0, "dist": 98.0, "visee": false},
]
const MARGE_ATTAQUE_X := 118.0
const MARGE_ATTAQUE_Y := 112.0
## Portrait (toléré) : deux rangées au-dessus de l'attaque, dans une colonne étroite qui laisse
## ~48 % de la largeur au pouce gauche. [angle, distance].
const EVENTAIL_PORTRAIT := {"dash": [248.0, 108.0], "skill": [294.0, 118.0], "super": [255.0, 197.0], "gadget": [288.0, 194.0]}
const MARGE_PORTRAIT_X := 95.0
const MARGE_PORTRAIT_Y := 115.0

var largeur := 1.0
var hauteur := 1.0
var echelle := 1.0
var marges := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
## Abscisse où s'arrête la zone du joystick.
var zone_x := 0.0
var manche := {"doigt": AUCUN, "baseX": 0.0, "baseY": 0.0, "knobX": 0.0, "knobY": 0.0, "drawX": 0.0, "drawY": 0.0, "x": 0.0, "y": 0.0}
var boutons: Array[Dictionary] = []

var _fronts: Dictionary # partagé avec la racine : attack, dash, skill, gadget, super, skillAimX, skillAimY

func _init(fronts: Dictionary) -> void:
	_fronts = fronts
	for modele: Dictionary in BOUTONS:
		var b: Dictionary = modele.duplicate()
		b.merge({"x": 0.0, "y": 0.0, "r": modele.rayon, "doigt": AUCUN, "ox": 0.0, "oy": 0.0, "dx": 0.0, "dy": 0.0, "glisse": false, "manuel": false})
		boutons.append(b)

## Place les boutons pour un viewport de `taille`, des marges sûres {top, right, bottom, left}
## (unités du viewport) et une échelle (unités du viewport par px CSS).
func disposer(taille: Vector2, marges_sures: Dictionary, echelle_css: float = 1.0) -> void:
	largeur = taille.x
	hauteur = taille.y
	marges = marges_sures
	echelle = echelle_css
	var portrait := hauteur > largeur
	var ax: float = largeur - (MARGE_PORTRAIT_X if portrait else MARGE_ATTAQUE_X) * echelle - marges.right
	var ay: float = hauteur - (MARGE_PORTRAIT_Y if portrait else MARGE_ATTAQUE_Y) * echelle - marges.bottom
	var gauche := INF
	for b in boutons:
		var polaire: Array = [b.angle, b.dist]
		if portrait and EVENTAIL_PORTRAIT.has(b.id):
			polaire = EVENTAIL_PORTRAIT[b.id]
		var a := deg_to_rad(polaire[0])
		b.r = b.rayon * echelle
		b.x = ax + cos(a) * polaire[1] * echelle
		b.y = ay + sin(a) * polaire[1] * echelle
		gauche = minf(gauche, b.x - b.r * TOLERANCE_POUCE)
	# La zone joystick s'arrête avant la zone de toucher du bouton le plus à gauche.
	zone_x = minf(largeur * ZONE_DEPLACEMENT, gauche - ECART_ZONE * echelle)

## Le bouton sous le point (zone de toucher plus large que le dessin), ou null.
func bouton_a(x: float, y: float) -> Variant:
	var meilleur: Variant = null
	var meilleure_d := INF
	for b in boutons:
		var d := sqrt((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y))
		if d < b.r * TOLERANCE_POUCE and d < meilleure_d:
			meilleur = b
			meilleure_d = d
	return meilleur

func appuyer(doigt: int, p: Vector2) -> void:
	var vise: Variant = bouton_a(p.x, p.y)
	var b: Variant = vise
	# Un toucher dans la moitié droite hors de tout bouton = attaque, visée depuis ce point.
	if b == null and p.x >= zone_x and boutons[0].doigt == AUCUN:
		b = boutons[0]
	if b != null and b.doigt == AUCUN:
		_prendre(b, doigt, p, vise == null)
		return
	if p.x < zone_x and manche.doigt == AUCUN:
		# Origine LOGIQUE = le point de contact : un pouce posé sans bouger ne fait jamais
		# courir le héros, même collé au bord. Seul le DESSIN est recalé loin des bords.
		manche.doigt = doigt
		manche.baseX = p.x
		manche.baseY = p.y
		_bouger_manche(p.x, p.y)

func _prendre(b: Dictionary, doigt: int, p: Vector2, hors_bouton: bool) -> void:
	var flottant: bool = b.id == "attack" and hors_bouton
	b.doigt = doigt
	b.ox = p.x if flottant else b.x
	b.oy = p.y if flottant else b.y
	b.dx = 0.0
	b.dy = 0.0
	b.glisse = false
	b.manuel = false
	# La compétence part au RELÂCHER ; tout le reste part à l'appui.
	if b.id != "skill":
		_fronts[b.id] = true

func glisser(doigt: int, p: Vector2) -> void:
	if manche.doigt == doigt:
		_bouger_manche(p.x, p.y)
		return
	for b in boutons:
		if b.doigt != doigt:
			continue
		b.dx = p.x - b.ox
		b.dy = p.y - b.oy
		var d := sqrt(b.dx * b.dx + b.dy * b.dy)
		if b.visee and d > VISEE_GLISSER_MIN * echelle:
			b.glisse = true
			b.manuel = true
		elif b.manuel and d < VISEE_ANNULER * echelle:
			b.glisse = false # retour au centre : la compétence est annulée au relâcher

func relacher(doigt: int, annule: bool = false) -> void:
	if manche.doigt == doigt:
		_lacher_manche()
		return
	for b in boutons:
		if b.doigt != doigt:
			continue
		var perdu: bool = annule or (b.manuel and not b.glisse)
		if b.id == "skill" and not perdu:
			# Compétence : dans la direction glissée (ou assistée sur un tap).
			var l := sqrt(b.dx * b.dx + b.dy * b.dy)
			var vise: bool = b.glisse and l > 0.0
			_fronts.skillAimX = b.dx / l if vise else 0.0
			_fronts.skillAimY = b.dy / l if vise else 0.0
			_fronts.skill = true
		_lacher_bouton(b)

## Perte du focus : plus aucun doigt ne tient rien.
func tout_relacher() -> void:
	_lacher_manche()
	for b in boutons:
		_lacher_bouton(b)

func _lacher_manche() -> void:
	manche.doigt = AUCUN
	manche.x = 0.0
	manche.y = 0.0

func _lacher_bouton(b: Dictionary) -> void:
	b.doigt = AUCUN
	b.glisse = false
	b.manuel = false
	b.dx = 0.0
	b.dy = 0.0

func _bouger_manche(x: float, y: float) -> void:
	var s := manche
	var course := RAYON_MANCHE * echelle
	var dx: float = x - s.baseX
	var dy: float = y - s.baseY
	var d := sqrt(dx * dx + dy * dy)
	if d > course:
		# Joystick « suiveur » : la base glisse derrière le pouce au-delà de la course.
		s.baseX += dx / d * (d - course)
		s.baseY += dy / d * (d - course)
		dx = x - s.baseX
		dy = y - s.baseY
	s.knobX = s.baseX + dx
	s.knobY = s.baseY + dy
	var bord := course + MARGE_DESSIN * echelle
	s.drawX = maxf(bord + marges.left, minf(s.baseX, zone_x - course))
	s.drawY = maxf(bord, minf(s.baseY, hauteur - bord - marges.bottom))
	var l := sqrt(dx * dx + dy * dy)
	var n := minf(1.0, l / course)
	var force := 0.0 if n < MANCHE_MORT else minf(1.0, (n - MANCHE_MORT) / (MANCHE_PLEIN - MANCHE_MORT))
	if l == 0.0:
		l = 1.0
	s.x = dx / l * force
	s.y = dy / l * force

## Pose dans l'InputFrame ce que les doigts tiennent : déplacement, attaque maintenue, visée.
func completer(f: Dictionary) -> void:
	if manche.doigt != AUCUN:
		f.moveX = manche.x
		f.moveY = manche.y
	var atk := boutons[0]
	if atk.doigt == AUCUN:
		return
	f.attack = true
	if atk.glisse:
		var l := sqrt(atk.dx * atk.dx + atk.dy * atk.dy)
		if l == 0.0:
			l = 1.0
		f.aimX = atk.dx / l
		f.aimY = atk.dy / l

## La disposition pour le HUD (même forme que touchUI() du web), en unités du viewport.
## `stick.baseX/Y` est la base À DESSINER (recalée loin des bords), `knobX/Y` le pommeau à
## dessiner ; `stick.r` est la course (58 px CSS à l'échelle).
func interface(visible: bool) -> Dictionary:
	var s := manche
	var liste: Array = []
	for b in boutons:
		liste.append({"id": b.id, "x": b.x, "y": b.y, "r": b.r, "pressed": b.doigt != AUCUN, "dragging": b.glisse, "dx": b.dx, "dy": b.dy})
	var stick := {
		"active": s.doigt != AUCUN,
		"baseX": s.drawX, "baseY": s.drawY,
		"knobX": s.drawX + (s.knobX - s.baseX), "knobY": s.drawY + (s.knobY - s.baseY),
		"r": RAYON_MANCHE * echelle,
	}
	return {"visible": visible, "stick": stick, "buttons": liste}
