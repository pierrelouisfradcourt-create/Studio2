extends RefCounted
## Le tactile multi-doigts : joystick flottant dans la moitié gauche, boutons à la Brawl Stars à
## droite. Portage fidèle de GAMES/dungeon_666/src/input/input.mjs (layout, buttonAt,
## onPointerDown / Move / Up, updateStick, touchUI). Ne dessine rien, ne connaît pas la partie.
##
## Les longueurs sont en « px CSS » dans la version web : ici elles sont multipliées par
## `echelle` (unités du viewport par px CSS) pour garder la même taille sous le pouce.
##
## COMBAT V3, disposition : le GROS bouton d'attaque en bas à droite, les trois emplacements
## (skill1, skill2, skill3) en ARC autour de lui, à gauche et au-dessus, et le DASH à part, de
## l'autre côté (à droite, contre le bord) : le pouce y va en se repliant, sans croiser l'arc.
##
## COMBAT V3, gestes. Bouton d'attaque (ou toucher flottant dans la moitié droite) :
##   - appui BREF, relâché sans glisser : UN coup, au relâcher, visée assistée ;
##   - GLISSER : vise sans rien lancer ; UN coup part au relâcher, dans la direction glissée ;
##     revenir au centre avant de relâcher ANNULE ;
##   - appui MAINTENU sans glisser (APPUI_BREF_MS passées) : le coup part, puis l'attaque est
##     TENUE jusqu'au relâcher (elle enchaîne, et c'est ce qui arme l'ultime, jauge pleine).
## Rien ne part donc à l'appui : c'est ce qui évite les deux coups d'un glisser.
## Emplacements : tout part au RELÂCHER (tap = visée assistée, glisser = viser, retour au centre
## = annuler). Dash : à l'appui.

const RAYON_MANCHE := 58.0 # course du joystick de déplacement
const MANCHE_MORT := 0.12 # fraction du rayon ignorée
const MANCHE_PLEIN := 0.7 # fraction du rayon où la vitesse est maximale (nervosité)
const VISEE_GLISSER_MIN := 18.0 # en deçà, un relâcher = tap (visée assistée)
const VISEE_ANNULER := 12.0 # après une visée manuelle, revenir au centre ANNULE la compétence
const ZONE_DEPLACEMENT := 0.48 # moitié gauche (fraction de la largeur) réservée au déplacement
const TOLERANCE_POUCE := 1.35 # zone de toucher = rayon dessiné × 1,35
const ECART_ZONE := 8.0 # entre la zone joystick et la zone de toucher du bouton le plus à gauche
const MARGE_DESSIN := 12.0 # le DESSIN du joystick reste à cette distance des bords
const APPUI_BREF_MS := 150.0 # pouce posé sans glisser plus longtemps : l'attaque est TENUE
const AUCUN := -1 # aucun doigt

## Disposition autour du bouton d'attaque (px CSS ; angles en degrés, y vers le bas : 180 = à
## gauche, 270 = au-dessus). Les trois emplacements sur un même arc (rayon 106), de 45° en 45° :
## cibles de 60 px, 21 px de vide entre deux voisins, 24 px entre eux et l'attaque. Le dash de
## l'autre côté de l'attaque, un peu plus bas : là où le pouce arrive en se repliant.
const BOUTONS := [
	{"id": "attack", "rayon": 52.0, "angle": 0.0, "dist": 0.0, "visee": true},
	{"id": "dash", "rayon": 38.0, "angle": 12.0, "dist": 106.0, "visee": false},
	{"id": "skill1", "rayon": 30.0, "angle": 190.0, "dist": 106.0, "visee": true},
	{"id": "skill2", "rayon": 30.0, "angle": 235.0, "dist": 106.0, "visee": true},
	{"id": "skill3", "rayon": 30.0, "angle": 280.0, "dist": 106.0, "visee": true},
]
const MARGE_ATTAQUE_X := 168.0
const MARGE_ATTAQUE_Y := 100.0
## Portrait (toléré) : pas de place à droite de l'attaque ; le dash passe au-dessus de l'arc, dans
## une colonne étroite qui laisse ~43 % de la largeur au pouce gauche. [angle, distance].
const EVENTAIL_PORTRAIT := {"dash": [262.0, 200.0], "skill1": [185.0, 106.0], "skill2": [232.0, 106.0], "skill3": [279.0, 106.0]}
const MARGE_PORTRAIT_X := 70.0
const MARGE_PORTRAIT_Y := 115.0

var largeur := 1.0
var hauteur := 1.0
var echelle := 1.0
var marges := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
## Abscisse où s'arrête la zone du joystick.
var zone_x := 0.0
var manche := {"doigt": AUCUN, "baseX": 0.0, "baseY": 0.0, "knobX": 0.0, "knobY": 0.0, "drawX": 0.0, "drawY": 0.0, "x": 0.0, "y": 0.0}
var boutons: Array[Dictionary] = []

var _fronts: Dictionary # partagé avec la racine : attack, dash, skill1..3, leurs visées, aimX, aimY

func _init(fronts: Dictionary) -> void:
	_fronts = fronts
	for modele: Dictionary in BOUTONS:
		var b: Dictionary = modele.duplicate()
		b.merge({"x": 0.0, "y": 0.0, "r": modele.rayon, "doigt": AUCUN, "ox": 0.0, "oy": 0.0, "dx": 0.0, "dy": 0.0, "glisse": false, "manuel": false, "tenu": false, "pose_ms": 0.0})
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
	b.tenu = false
	b.pose_ms = float(Time.get_ticks_msec())
	# Seul le dash part à l'appui : l'attaque attend de savoir si le pouce tape, glisse ou tient.
	if b.id == "dash":
		_fronts.dash = true

static func _emplacement(b: Dictionary) -> bool:
	return String(b.id).begins_with("skill")

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
			b.tenu = false # viser n'est pas tenir : ni combo enchaîné, ni ultime armé
		elif b.manuel and d < VISEE_ANNULER * echelle:
			b.glisse = false # retour au centre : l'action est annulée au relâcher

func relacher(doigt: int, annule: bool = false) -> void:
	if manche.doigt == doigt:
		_lacher_manche()
		return
	for b in boutons:
		if b.doigt != doigt:
			continue
		var perdu: bool = annule or (b.manuel and not b.glisse) # annulé par le système, ou ramené au centre
		var l := sqrt(b.dx * b.dx + b.dy * b.dy)
		var vise: bool = b.glisse and l > 0.0
		# Un emplacement part toujours au relâcher ; l'attaque aussi, sauf si elle a été TENUE (ses
		# coups sont déjà partis). Dans la direction glissée, ou assistée sur un tap.
		var part: bool = _emplacement(b) or (b.id == "attack" and not b.tenu)
		if part and not perdu:
			var cle: String = "aim" if b.id == "attack" else b.id + "Aim"
			_fronts[cle + "X"] = b.dx / l if vise else 0.0
			_fronts[cle + "Y"] = b.dy / l if vise else 0.0
			_fronts[b.id] = true
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
	b.tenu = false
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

## Pose dans l'InputFrame ce que les doigts tiennent : déplacement, attaque TENUE, visée.
## Le pouce qui GLISSE sur l'attaque vise sans la tenir : ni combo enchaîné, ni ultime armé.
func completer(f: Dictionary) -> void:
	if manche.doigt != AUCUN:
		f.moveX = manche.x
		f.moveY = manche.y
	var atk := boutons[0]
	if atk.doigt == AUCUN:
		return
	if atk.glisse:
		var l := sqrt(atk.dx * atk.dx + atk.dy * atk.dy)
		if l == 0.0:
			l = 1.0
		f.aimX = atk.dx / l
		f.aimY = atk.dy / l
		return
	# Pouce resté posé sans glisser : passé l'appui bref, le coup part et l'attaque est tenue.
	if not atk.tenu and not atk.manuel and float(Time.get_ticks_msec()) - atk.pose_ms >= APPUI_BREF_MS:
		atk.tenu = true
		f.attackPressed = true
	if atk.tenu:
		f.attack = true

## La disposition pour le HUD (même forme que touchUI() du web), en unités du viewport.
## `stick.baseX/Y` est la base À DESSINER (recalée loin des bords), `knobX/Y` le pommeau à
## dessiner ; `stick.r` est la course (58 px CSS à l'échelle). Un bouton : `pressed` (un doigt le
## tient), `dragging` (il vise : dx, dy depuis son origine), `held` (attaque tenue).
func interface(visible: bool) -> Dictionary:
	var s := manche
	var liste: Array = []
	for b in boutons:
		liste.append({"id": b.id, "x": b.x, "y": b.y, "r": b.r, "pressed": b.doigt != AUCUN, "dragging": b.glisse, "dx": b.dx, "dy": b.dy, "held": b.tenu})
	var stick := {
		"active": s.doigt != AUCUN,
		"baseX": s.drawX, "baseY": s.drawY,
		"knobX": s.drawX + (s.knobX - s.baseX), "knobY": s.drawY + (s.knobY - s.baseY),
		"r": RAYON_MANCHE * echelle,
	}
	return {"visible": visible, "stick": stick, "buttons": liste}
