extends "res://jeu/monde/creatures/calque.gd"
## Calque des ALLIÉS, lus dans game.allies : les LIMIERS de la Meute des Limbes (ultime de la
## Chasseresse), depuis l'étape 4 son LEURRE D'OS (`kind` : "leurre", dessiné par _leurre) et, depuis
## l'étape 5, l'OMBRE JUMELLE du Revenant (`kind` : "ombre", dessinée par _ombre_jumelle). Chaque limier vivant a son nœud, enfant de ce calque trié du fond vers l'avant avec
## les ennemis, le héros et les piliers (groupe Debout d'entites.gd). Un limier est UN lot de
## triangles (le pinceau) : 1 appel de dessin, ombre, barre de vie et repère de durée compris.
## Ce qui les distingue d'un ennemi au premier regard : la teinte FROIDE de l'héroïne (os clair,
## cyan, contour bleu nuit — jamais de rouge), une silhouette longue et basse de chien de chasse.
## Ce qui se lit sur chacun : sa vie (petite barre froide au-dessus de lui), sa durée (un arc cyan
## à ses pieds qui se vide), sa cible (il la regarde ; gueule ouverte quand il mord).
## Aucune règle ici : tout est lu (x, y, face, state, biteT, hp, life).

const NUIT := Color("#0d2a36") # le contour du héros : même famille
const OS_CLAIR := Color("#dff6ff")
const OS_OMBRE := Color("#8fc4d6")
const SAUT := 150.0 # u : au-delà, ce n'est pas un pas
const MORSURE := 0.16 # s : la gueule reste ouverte après une morsure
const VISUEL := 1.35 # le limier est dessiné un peu plus grand que son cercle de collision (comme le héros)

var _noeuds := {} # id de limier -> {n: Node2D, marche, avant, mord, a}

func _init() -> void:
	super()
	y_sort_enabled = true

## Une image : chaque limier vivant a son nœud, qui le suit ; les nœuds sans limier sont rendus.
func actualiser(delta: float) -> void:
	var g = jeu()
	var vus := {}
	if g != null:
		for a in g.get("allies", []):
			if D6Js.truthy(a.get("dead")):
				continue
			vus[a.id] = true
			_suivre(a, g, delta)
	if vus.size() != _noeuds.size():
		for id in _noeuds.keys():
			if not vus.has(id):
				_noeuds[id].n.queue_free()
				_noeuds.erase(id)

func _suivre(a: Dictionary, g: Dictionary, delta: float) -> void:
	var etat = _noeuds.get(a.id)
	if etat == null:
		var n := Node2D.new()
		add_child(n)
		etat = {"n": n, "marche": 0.0, "avant": Vector2.INF, "mord": 0.0, "a": a}
		n.draw.connect(_peindre.bind(etat))
		_noeuds[a.id] = etat
	etat.a = a
	var pos := Vector2(a.x, a.y)
	var d: float = 0.0 if etat.avant == Vector2.INF else pos.distance_to(etat.avant)
	etat.avant = pos
	if d < SAUT:
		etat.marche += d * PI / (a.r * 2.2)
	# La morsure vient de partir quand sa recharge est presque pleine (biteT repart de biteEvery).
	var s: Dictionary = g.tuning["super"]
	var vient_de_mordre: bool = a.state == "bite" and nombre(a, "biteT") > nombre(s, "biteEvery") - MORSURE
	etat.mord = MORSURE if vient_de_mordre else maxf(0.0, etat.mord - delta)
	etat.n.position = pos
	etat.n.queue_redraw()

## Dessin d'un limier dans le repère de son nœud (origine à ses pieds).
func _peindre(etat: Dictionary) -> void:
	var a: Dictionary = etat.a
	var n: Node2D = etat.n
	var r: float = a.r * VISUEL
	p.commencer(n)
	if a.kind == "leurre" or a.kind == "ombre":
		if a.kind == "leurre":
			_leurre(a, r)
		else:
			_ombre_jumelle(a, r)
		p.finir()
		p.ci = self
		return
	p.ombre(Vector2(0.0, r * 0.35), r * 1.7, r * 0.8, 0.8)
	_duree(a, r)
	var bond: float = sin(etat.marche) * 1.5 if a.state == "chase" else 0.0
	var mord: float = etat.mord / MORSURE
	p.poser(Transform2D(a.face, Vector2(0.0, -r * 0.25 - absf(bond))) * Transform2D(0.0, Vector2(r * 0.4 * mord, 0.0)))
	_corps(a, r, etat.marche, mord)
	p.lever()
	_vie(a, r)
	p.finir()
	p.ci = self

## LEURRE D'OS (Chasseresse, étape 4) : un épouvantail d'os planté là — pieu, traverse, haillons à la
## teinte de l'héroïne, crâne — qui oscille un peu. À ses pieds le même arc de durée que les limiers ;
## autour, un cercle fin : jusqu'où il attire la mêlée (lu : a.lure.range). Sa vie : la même barre.
func _leurre(a: Dictionary, r: float) -> void:
	var os: Color = Color.WHITE if a.flash > 0.0 else OS_CLAIR
	var pied := Vector2(0.0, r * 0.35)
	var penche := sin(temps() * 3.0 + a.id) * r * 0.08
	var lure = a.get("lure")
	if lure is Dictionary:
		p.anneau(pied, lure.range, Color(PAL.heroCape, 0.16), 1.5)
	p.ombre(pied, r * 1.3, r * 0.6, 0.8)
	_duree(a, r)
	p.baton(pied, Vector2(penche, -r * 2.1), OS_OMBRE, 3.5, NUIT)
	p.baton(Vector2(-r * 1.15 + penche, -r * 1.45), Vector2(r * 1.15 + penche, -r * 1.45), os, 3.0, NUIT)
	for cote: float in [-1.0, 1.0]:
		p.pic(Vector2(cote * r * 1.05 + penche, -r * 1.4), Vector2(cote * r * 0.5 + penche, -r * 1.4), Vector2(cote * r * 0.85 + penche * 2.5, -r * 0.5), Color(PAL.heroCape, 0.9), NUIT, 1.5)
	p.lueur(Vector2(penche, -r * 1.5), r * 1.5, PAL.heroCape, 0.5)
	var tete := Vector2(penche, -r * 2.35)
	p.disque(tete, r * 0.55, os, NUIT, 2.0)
	for cote: float in [-1.0, 1.0]:
		p.disque(tete + Vector2(cote * r * 0.2, -r * 0.03), r * 0.13, NUIT, Pinceau.SANS)
	p.pic(tete + Vector2(-r * 0.22, r * 0.3), tete + Vector2(r * 0.22, r * 0.3), tete + Vector2(0.0, r * 0.62), os, NUIT, 1.5)
	var part := clampf(a.hp / maxf(1.0, a.maxHp), 0.0, 1.0)
	var largeur := r * 2.4
	var coin := Vector2(-largeur * 0.5, -r * 3.3)
	p.rect(Rect2(coin - Vector2(1.0, 1.0), Vector2(largeur + 2.0, 5.0)), Color(NUIT, 0.75))
	p.rect(Rect2(coin, Vector2(largeur * part, 3.0)), PAL.heroCape if part > 0.35 else OS_CLAIR)

## OMBRE JUMELLE (Revenant, étape 5) : sa silhouette sans visage, en nuit cernée de la teinte froide du
## héros, qui s'effiloche vers le sol (elle ne marche pas : elle flotte). Deux yeux clairs, une lame
## claire : au repos le long du corps, FAUCHÉE devant elle le temps qu'elle répète un coup (lu :
## a.biteT, a.face). À ses pieds, l'arc de durée des alliés. Intangible : ni barre de vie, ni cercle.
func _ombre_jumelle(a: Dictionary, r: float) -> void:
	var pied := Vector2(0.0, r * 0.35)
	var souffle := 0.5 + 0.5 * sin(temps() * 5.0 + a.id)
	var flotte := sin(temps() * 3.0 + a.id) * r * 0.18
	p.ombre(pied, r * 1.15, r * 0.5, 0.55)
	_duree(a, r)
	var corps := Color(NUIT, 0.9)
	p.lueur(Vector2(0.0, -r * 1.2), r * 2.0, PAL.heroCape, 0.3 + 0.25 * souffle)
	p.pic(Vector2(-r * 0.8, -r * 1.25), Vector2(r * 0.8, -r * 1.25), pied + Vector2(flotte, 0.0), corps, PAL.heroCape, 1.5)
	p.ellipse(Vector2(0.0, -r * 1.3), r * 0.82, r * 0.7, corps, PAL.heroCape, 1.5)
	var tete := Vector2(0.0, -r * 2.15)
	p.disque(tete, r * 0.5, corps, PAL.heroCape, 1.5)
	for cote: float in [-1.0, 1.0]:
		p.disque(tete + Vector2(cote * r * 0.19, 0.0), r * 0.1, OS_CLAIR, Pinceau.SANS)
	var coup := clampf(nombre(a, "biteT") / 0.18, 0.0, 1.0)
	var dir := Vector2.from_angle(a.face)
	var main := Vector2(0.0, -r * 1.2) + dir * r * 0.7
	if coup > 0.0:
		p.taillade(Vector2(0.0, -r * 1.2), r * 3.4, a.face - 1.1, a.face + 1.1, r * 0.5, PAL.heroCape, coup)
		p.baton(main, main + dir.rotated(lerpf(0.9, -0.9, coup)) * r * 2.2, Color.WHITE, 3.0, NUIT)
	else:
		p.baton(main, main + Vector2(dir.x * 0.4, 0.9).normalized() * r * 1.6, OS_CLAIR, 2.5, NUIT)

## Repère de durée : à ses pieds, un arc cyan qui se vide avec le temps qui lui reste.
func _duree(a: Dictionary, r: float) -> void:
	var reste := clampf(a.life / maxf(1e-3, a.lifeMax), 0.0, 1.0)
	var c := Vector2(0.0, r * 0.35)
	p.anneau(c, r * 1.75, Color(NUIT, 0.45), 2.5)
	p.arc(c, r * 1.75, -PI / 2.0, -PI / 2.0 + TAU * reste, Color(PAL.heroCape, 0.9 if reste > 0.2 or int(temps() * 8.0) % 2 == 0 else 0.35), 2.5)

## Le chien d'os, x = devant lui : queue, pattes, cage thoracique, crâne long, mâchoire.
func _corps(a: Dictionary, r: float, marche: float, mord: float) -> void:
	var touche: bool = a.flash > 0.0
	var os: Color = Color.WHITE if touche else OS_CLAIR
	var court: bool = a.state == "chase"
	var pas: float = sin(marche) if court else 0.0
	# Queue : trois vertèbres qui battent.
	var onde := sin(temps() * 9.0 + a.id) * r * 0.25
	p.ruban(PackedVector2Array([Vector2(-r * 1.1, 0.0), Vector2(-r * 1.7, onde * 0.5), Vector2(-r * 2.2, onde)]), os, 2.5, NUIT)
	# Pattes : deux paires qui se croisent en courant.
	for cote: float in [-1.0, 1.0]:
		for bout: float in [-1.0, 1.0]:
			var x: float = r * (0.75 * bout + 0.35 * pas * cote * bout)
			p.baton(Vector2(r * 0.7 * bout, r * 0.3 * cote), Vector2(x, r * 0.85 * cote), os, 2.5, NUIT)
	# Cage thoracique : un fuseau sombre, des côtes claires, l'échine.
	p.ellipse(Vector2(-r * 0.1, 0.0), r * 1.15, r * 0.62, Color(NUIT, 0.92), NUIT, 2.0)
	for i in 4:
		var x: float = r * (-0.75 + 0.42 * i)
		var demi: float = r * (0.5 - 0.06 * absf(i - 1.5))
		p.ligne(Vector2(x, -demi), Vector2(x + r * 0.12, demi), os, 2.0)
	p.ligne(Vector2(-r * 1.1, 0.0), Vector2(r * 0.95, 0.0), OS_OMBRE, 2.0)
	p.lueur(Vector2(-r * 0.1, 0.0), r * 0.9, PAL.heroCape, 0.55)
	# Crâne : une tête longue, un museau en pointe, la mâchoire qui s'ouvre à la morsure.
	var tete := Vector2(r * 1.3, 0.0)
	var gueule: float = 0.18 + 0.5 * mord
	for cote: float in [-1.0, 1.0]:
		p.pic(tete + Vector2(0.0, r * 0.1 * cote), tete + Vector2(r * 0.2, r * (0.3 + gueule * 0.5) * cote), tete + Vector2(r * 1.15, r * gueule * cote), os, NUIT, 1.5)
	p.disque(tete, r * 0.5, os, NUIT, 2.0)
	for cote: float in [-1.0, 1.0]:
		p.pic(tete + Vector2(-r * 0.3, r * 0.3 * cote), tete + Vector2(-r * 0.05, r * 0.45 * cote), tete + Vector2(-r * 0.7, r * 0.75 * cote), OS_OMBRE, NUIT, 1.5)
		p.disque(tete + Vector2(r * 0.12, r * 0.2 * cote), r * 0.13, PAL.heroCape, Pinceau.SANS)

## Barre de vie discrète au-dessus de lui : froide, fine, sans cadre épais.
func _vie(a: Dictionary, r: float) -> void:
	var part := clampf(a.hp / maxf(1.0, a.maxHp), 0.0, 1.0)
	var largeur := r * 2.4
	var coin := Vector2(-largeur * 0.5, -r * 2.3)
	p.rect(Rect2(coin - Vector2(1.0, 1.0), Vector2(largeur + 2.0, 5.0)), Color(NUIT, 0.75))
	p.rect(Rect2(coin, Vector2(largeur * part, 3.0)), PAL.heroCape if part > 0.35 else OS_CLAIR)
