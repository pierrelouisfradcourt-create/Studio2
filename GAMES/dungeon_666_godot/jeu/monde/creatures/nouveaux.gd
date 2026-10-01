extends "res://jeu/monde/creatures/archetypes.gd"
## Les trois ARCHÉTYPES du bestiaire ajouté (2026-10-01). Même repère et mêmes outils que
## archetypes.gd (x = devant lui). Chacun se lit à sa silhouette ET à son état :
##   porte-pavois    trapu, rouille ; grand PAVOIS de bronze sur l'arc de garde RÉEL (guardArc),
##                   centré sur e.face ; dos nu, échine sombre. Pavois levé / écarté et terni
##                   pendant sa récupération (« frappe maintenant ») / tombé à terre s'il est étourdi
##   traqueur        amande mince, prune, yeux magenta, deux lames. Il se dissout dans sa fumée
##                   (fade), resurgit dans une volute lames levées (windup), puis reste essoufflé,
##                   lames basses (recover)
##   porte-étendard  rond, ocre ; haute hampe dressée vers le haut de l'écran, étendard cramoisi à
##                   deux pointes qui flotte ; couché et terne s'il est étourdi

const BRONZE := Color("#e0b24a")
const BRONZE_TERNI := Color("#77664a")
const BOSSAGE := Color("#fff0b8")
const MAGENTA := Color("#ff3cbe")
const ACIER_PRUNE := Color("#ecd6f4")
const FUMEE := Color("#7a4a78")
const CRAMOISI := Color("#e0283c")
const VOLUTE := 0.45 # s : durée de la volute de fumée à la réapparition du Traqueur

func dessiner(e: Dictionary, r: float, corps: Color, g: Dictionary, noeud: Node2D, horloge: float) -> void:
	_poser_corps(noeud, horloge)
	match e.kind:
		"pavois": pavois(e, r, corps, g)
		"stalker": traqueur(e, r, corps, g)
		_: etendard(e, r, corps)

# ---------------------------------------------------------------- Porte-pavois

func pavois(e: Dictionary, r: float, corps: Color, g: Dictionary) -> void:
	var ouverture: float = g.tuning.enemies.pavois.guardArc
	var leve: bool = D6FoeDefense.guard_up(g, e)
	if e.stun > 0.0:
		_pavois_tombe(r)
	pieds(r, 0.6, corps.darkened(0.55))
	p.ellipse(Vector2(-0.05 * r, 0.0), r * 0.96, r * 1.12, corps, Pinceau.ENCRE, 3.0)
	_dos_nu(r, corps)
	p.disque(Vector2(0.28 * r, 0.0), r * 0.52, corps.darkened(0.45), Pinceau.ENCRE, 2.5)
	p.yeux(Vector2(0.28 * r, 0.0), r, PAL.crit if leve else Color.WHITE, 0.5, 0.36, 0.11)
	if leve:
		var recul: float = n.anticipation if e.state == "windup" else 0.0
		_pavois_leve(r, 0.0, ouverture, r * (1.38 - 0.3 * recul), BRONZE, true)
	elif e.stun <= 0.0:
		_pavois_leve(r, 1.9, ouverture * 0.75, r * 1.2, BRONZE_TERNI, false)

## Le dos : peau nue plus claire, échine sombre et ses vertèbres — c'est là qu'il faut frapper.
func _dos_nu(r: float, corps: Color) -> void:
	p.calotte(Vector2(-0.05 * r, 0.0), r * 0.9, PI - 1.15, PI + 1.15, corps.lightened(0.22))
	p.ligne(Vector2(-0.9, 0.0) * r, Vector2(-0.3, 0.0) * r, corps.darkened(0.6), 3.0)
	for i in 3:
		p.disque(Vector2(-0.78 + i * 0.2, 0.0) * r, r * 0.09, corps.darkened(0.6), Pinceau.SANS)

## Le pavois : un arc épais de `ouverture` rad centré sur `axe`, à `rayon` du centre ; un bossage
## clair en son milieu dit où il regarde.
func _pavois_leve(r: float, axe: float, ouverture: float, rayon: float, bronze: Color, brille: bool) -> void:
	var demi := r * 0.23
	var bord := Pinceau.pts_arc(Vector2.ZERO, rayon + demi, axe - ouverture * 0.5, axe + ouverture * 0.5, 14)
	bord.append_array(Pinceau.pts_arc(Vector2.ZERO, rayon - demi, axe + ouverture * 0.5, axe - ouverture * 0.5, 14))
	p.forme(bord, bronze, Pinceau.ENCRE, 3.0)
	p.arc(Vector2.ZERO, rayon + demi * 0.4, axe - ouverture * 0.5 + 0.1, axe + ouverture * 0.5 - 0.1, bronze.lightened(0.45) if brille else bronze.darkened(0.25), 2.0)
	p.arc(Vector2.ZERO, rayon - demi * 0.45, axe - ouverture * 0.5 + 0.1, axe + ouverture * 0.5 - 0.1, bronze.darkened(0.3), 2.0)
	p.disque(Vector2.from_angle(axe) * rayon, r * 0.26, BOSSAGE if brille else bronze.lightened(0.15), Pinceau.ENCRE, 2.0)

## Étourdi : le pavois est tombé à plat devant lui, terne.
func _pavois_tombe(r: float) -> void:
	var centre := Vector2(0.95, 0.95) * r
	p.ellipse(centre, r * 0.82, r * 0.56, BRONZE_TERNI, Pinceau.ENCRE, 3.0, 0.6, 16)
	p.ellipse(centre, r * 0.55, r * 0.34, BRONZE_TERNI.darkened(0.2), Pinceau.SANS, 1.0, 0.6, 12)
	p.disque(centre, r * 0.16, BRONZE_TERNI.lightened(0.2), Pinceau.ENCRE, 1.5)

# ---------------------------------------------------------------- Traqueur

func traqueur(e: Dictionary, r: float, corps: Color, g: Dictionary) -> void:
	var etat: String = e.state
	var fond: float = clampf(e.stateTime / maxf(1e-3, g.tuning.enemies.stalker.fade), 0.0, 1.0) if etat == "fade" else 0.0
	var las: bool = etat == "recover"
	_fumee(e, r, etat, fond)
	p.alpha = lerpf(1.0, 0.1, fond)
	var fouet: float = sin(temps * 6.0 + e.id) * 0.3
	p.ruban(PackedVector2Array([Vector2(-1.05, 0.0) * r, Vector2(-1.65, fouet * 0.5) * r, Vector2(-2.25, fouet) * r]), corps.darkened(0.3), r * 0.2)
	_lames(r, etat, n.anticipation if etat == "windup" else 0.0)
	var long := 1.3 if las else 1.6
	var large := 0.74 if las else 0.62
	var amande := PackedVector2Array()
	for i in 16:
		var u := i / 8.0 if i <= 8 else (16 - i) / 8.0
		amande.append(Vector2(lerpf(-1.2, long, u), (large if i <= 8 else -large) * sin(PI * u)) * r)
	p.forme(amande, corps, Pinceau.ENCRE, 2.5)
	p.ligne(Vector2(-0.8, 0.0) * r, Vector2(0.3, 0.0) * r, corps.lightened(0.28), 2.5)
	var regard := Vector2((long - 0.75) * r, 0.0)
	p.lueur(regard, r * 1.1, MAGENTA, 0.25 if las else 0.6)
	for s: float in [-1.0, 1.0]:
		p.pic(regard + Vector2(-0.14, 0.12 * s) * r, regard + Vector2(0.1, 0.38 * s) * r, regard + Vector2(0.3, 0.13 * s) * r, MAGENTA.darkened(0.35) if las else MAGENTA, Pinceau.SANS)
	if las:
		var bouffee := 0.5 + 0.5 * sin(temps * 9.0)
		p.arc(Vector2((long + 0.15) * r, 0.0), r * (0.2 + 0.3 * bouffee), -0.9, 0.9, Color(1.0, 1.0, 1.0, 0.6 * (1.0 - bouffee)), 1.5)
	p.alpha = 1.0

## Les deux lames : le long du corps au repos, croisées quand il se dissout, écartées et levées
## quand il arme (leur fil s'allume), traînantes quand il récupère.
func _lames(r: float, etat: String, arme: float) -> void:
	var angle := -0.1
	var longueur := 1.5
	var pied := Vector2(0.0, 0.82)
	var teinte := ACIER_PRUNE
	match etat:
		"windup":
			angle = 0.35 + 0.75 * arme
			longueur = 1.95
			pied = Vector2(0.3, 0.78)
		"recover":
			angle = 2.45
			longueur = 1.35
			pied = Vector2(-0.15, 0.85)
			teinte = ACIER_PRUNE.darkened(0.35)
		"fade":
			angle = -0.75
			pied = Vector2(0.25, 0.7)
	for s: float in [-1.0, 1.0]:
		var base := Vector2(pied.x, pied.y * s) * r
		var dir := Vector2.from_angle(angle * s)
		var fil := dir.orthogonal() * r * 0.2
		p.pic(base + fil, base - fil, base + dir * r * longueur, teinte, Pinceau.ENCRE, 1.5)
		p.disque(base, r * 0.18, Color("#3a1230"), Pinceau.ENCRE, 1.5)
		if arme > 0.6:
			p.etoile(base + dir * r * longueur, r * 0.22 * arme, Color.WHITE, temps * 5.0, Pinceau.SANS)

## Fumée : elle monte et l'avale quand il se dissout ; elle s'ouvre en couronne quand il resurgit.
func _fumee(e: Dictionary, r: float, etat: String, fond: float) -> void:
	if etat == "fade":
		for i in 6:
			var a: float = i * TAU / 6.0 + 0.4 + e.id
			var c: Vector2 = Vector2.from_angle(a) * r * (1.1 - 0.5 * fond) + haut * r * (0.2 + 1.1 * fond * (0.5 + 0.5 * sin(i * 2.4)))
			p.disque(c, r * (0.25 + 0.5 * fond), Color(FUMEE, 0.25 + 0.4 * fond), Pinceau.SANS)
	elif etat == "windup" and e.stateTime < VOLUTE:
		var k: float = e.stateTime / VOLUTE
		for i in 8:
			var a: float = i * TAU / 8.0 + e.id + k * 1.2
			var c: Vector2 = Vector2.from_angle(a) * r * (0.7 + 1.9 * sqrt(k)) + haut * r * 0.6 * k
			p.disque(c, r * (0.62 - 0.3 * k), Color(FUMEE, 0.75 * (1.0 - k)), Pinceau.SANS)

# ---------------------------------------------------------------- Porte-étendard

func etendard(e: Dictionary, r: float, corps: Color) -> void:
	var couche: bool = e.stun > 0.0
	if couche:
		_etendard_couche(r)
	pieds(r, 0.5, corps.darkened(0.55))
	p.disque(Vector2.ZERO, r, corps, Pinceau.ENCRE, 3.0)
	p.calotte(Vector2.ZERO, r * 0.94, 1.95, TAU - 1.95, corps.darkened(0.38))
	p.arc(Vector2.ZERO, r * 0.74, -1.2, 1.2, corps.darkened(0.3), 2.0)
	for s: float in [-0.42, 0.42]:
		p.disque(Vector2.from_angle(s) * r * 0.56, r * 0.15, ORBITE, Pinceau.SANS)
	if not couche:
		_etendard_debout(e, r)

## La hampe, dressée vers le haut de l'écran depuis son épaule, et l'étendard à deux pointes qui
## flotte vers la droite de l'écran : on le voit de loin, par-dessus la mêlée.
func _etendard_debout(e: Dictionary, r: float) -> void:
	var pied := Vector2(-0.3, 0.55) * r
	var cime := pied + haut * r * 3.1
	p.baton(pied, cime, BOIS, 3.0)
	p.disque(pied + haut * r * 0.45, r * 0.22, Color("#8a6420"), Pinceau.ENCRE, 2.0)
	var toile := PackedVector2Array()
	var bas := PackedVector2Array()
	for i in 6:
		var u := i / 5.0
		var onde: float = sin(temps * 6.0 - u * 5.0 + e.id) * r * 0.16 * u
		var pli: float = sin(temps * 6.0 - u * 5.0 + e.id - 0.9) * r * 0.16 * u
		toile.append(cime - haut * r * 0.1 + droite * r * 2.0 * u + haut * onde)
		bas.append(cime - haut * r * 1.25 + droite * r * 2.0 * u + haut * pli)
	toile.append((toile[5] + bas[5]) * 0.5 - droite * r * 0.6)
	bas.reverse()
	toile.append_array(bas)
	p.forme(toile, CRAMOISI, Pinceau.ENCRE, 2.5)
	p.filet(PackedVector2Array([(toile[0] + toile[12]) * 0.5, (toile[2] + toile[10]) * 0.5, (toile[4] + toile[8]) * 0.5]), PAL.gold, 2.0)
	p.pic(cime - droite * r * 0.2, cime + droite * r * 0.2, cime + haut * r * 0.5, PAL.gold, Pinceau.ENCRE, 1.5)

## Étourdi : la hampe à terre, l'étendard affaissé et terne (la protection est tombée avec lui).
func _etendard_couche(r: float) -> void:
	var dir := (droite * 0.94 - haut * 0.34).normalized()
	var cote := dir.orthogonal()
	var pied := droite * r * 0.3
	p.baton(pied, pied + dir * r * 3.1, BOIS.darkened(0.3), 3.0)
	var a := pied + dir * r * 1.7
	var b := pied + dir * r * 3.0
	p.forme(PackedVector2Array([a, b, b - cote * r * 0.5, b - dir * r * 0.5 - cote * r * 0.8, b - cote * r * 1.15, a - cote * r * 0.95]),
		CRAMOISI.darkened(0.5), Pinceau.ENCRE, 2.5)
