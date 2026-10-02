extends "res://jeu/monde/creatures/calque.gd"
## Calque des ENNEMIS et des GARDIENS. Chaque ennemi vivant a son nœud (corps.gd), enfant de ce
## calque et trié du fond vers l'avant (y_sort). Le nœud porte le repère de la créature (position,
## regard, respiration, pas, anticipation, écrasement) ; ce calque-ci ne fait que tenir la liste
## des corps à jour et PEINDRE un corps quand son nœud le demande : marque d'élite, puis le dessin
## de son archétype (archetypes.gd, nouveaux.gd) ou de son modèle de Gardien (gardiens.gd).
## Coût : un corps n'est repeint que si sa pose change ou vingt fois par seconde ; entre deux, le
## moteur rejoue ses commandes sous un nouveau repère. Et un corps est UN lot de triangles (le
## pinceau, pinceau.gd) : 1 appel de dessin, lueurs comprises.

const Corps = preload("res://jeu/monde/creatures/corps.gd")
const Archetypes = preload("res://jeu/monde/creatures/archetypes.gd")
const Nouveaux = preload("res://jeu/monde/creatures/nouveaux.gd")
const Gardiens = preload("res://jeu/monde/creatures/gardiens.gd")

const NOUVEAUX := ["pavois", "stalker", "banner"]

var _teintes := {}
var _bestiaire: Archetypes
var _nouveaux: Nouveaux
var _gardiens: Gardiens
var _noeuds := {} # id d'ennemi -> son corps

func _init() -> void:
	super()
	y_sort_enabled = true
	_bestiaire = Archetypes.new(p)
	_nouveaux = Nouveaux.new(p)
	_gardiens = Gardiens.new(p)
	_teintes = {
		"imp": PAL.imp, "archer": PAL.archer, "brute": PAL.brute, "charger": PAL.charger, "exploder": PAL.exploder,
		"pyromancer": Color("#a8233a"), "necromancer": Color("#5a3690"),
		"pavois": Color("#8a4a2a"), "stalker": Color("#5a1f4a"), "banner": Color("#b5872f"),
		"gardien": PAL.boss, "cerbere": Color("#8a2e1e"), "minos": Color("#3a2e6e"), "colosse": Color("#6b5a50"),
	}

## Une image : chaque ennemi vivant a son corps, qui le suit ; les corps sans ennemi sont rendus.
func actualiser(delta: float) -> void:
	var g = jeu()
	if g == null:
		_rendre({})
		return
	var cible := lieu_heros(g)
	var vus := {}
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var n: Node2D = _noeuds.get(e.id)
		if n == null:
			n = Corps.new()
			n.calque = self
			_noeuds[e.id] = n
			add_child(n)
		vus[e.id] = true
		n.suivre(e, g, cible, delta)
	if vus.size() != _noeuds.size():
		_rendre(vus)

func _rendre(vus: Dictionary) -> void:
	for id in _noeuds.keys():
		if not vus.has(id):
			_noeuds[id].queue_free()
			_noeuds.erase(id)

## Dessin d'un corps, dans SON repère (origine au centre, x = devant lui). Appelé par son nœud.
## Un corps en plein bond est peint plus haut que son nœud, qui garde le rang de son point au sol.
func peindre(n: Node2D) -> void:
	var g = jeu()
	if g == null:
		return
	var e: Dictionary = n.e
	p.commencer(n)
	if n.envol > 0.0:
		p.poser(Transform2D(0.0, n.transform.affine_inverse().basis_xform(Vector2(0.0, -n.envol))))
	var r: float = e.r
	if D6Js.truthy(e.eliteMod):
		_marque_elite(e, r)
	var corps: Color = PAL.enemyFlash if e.flash > 0.0 else _teintes.get(e.kind, PAL.imp)
	if D6Js.truthy(e.boss):
		_gardiens.temps = temps()
		_gardiens.dessiner(e, r, n.rotation, corps)
	elif e.kind in NOUVEAUX:
		_nouveaux.dessiner(e, r, corps, g, n, temps())
	else:
		_bestiaire.dessiner(e, r, corps, g, n, temps())
	p.finir()
	p.ci = self

## Champion : anneau en tirets de sa couleur, qui tourne, et trois pointes de la même couleur
## dans son dos — on le reconnaît de loin, avant de lire son étiquette.
func _marque_elite(e: Dictionary, r: float) -> void:
	var teinte: Color = Couleurs.ELITE_COLORS[e.eliteMod]
	p.pointille(Vector2.ZERO, r + 7.0, teinte, 3.0, 14.0, -temps() * 30.0 / (r + 7.0))
	for i in 3:
		var d := Vector2.from_angle(PI + (i - 1) * 0.5)
		var cote := d.orthogonal() * r * 0.2
		p.pic(d * r * 0.9 + cote, d * r * 0.9 - cote, d * r * (1.55 if i == 1 else 1.32), teinte, Pinceau.ENCRE, 2.0)
