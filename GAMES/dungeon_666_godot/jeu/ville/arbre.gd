extends Control
## L'ARBRE DE COMPÉTENCES, dessiné à la manière de Diablo : les étages en BANDES, de haut en bas,
## le long d'un TRONC ; sur la branche de chaque étage, un MÉDAILLON par nœud (rond : compétence,
## losange : passif, écusson : déplacement et ultime) ; sous une compétence pendent, en fourche,
## ses deux améliorations exclusives. À gauche de chaque bande, le nom de l'étage et, s'il est
## fermé, ce qu'il lui faut (« 3 / 5 points dépensés ») ; le tronc se remplit d'or à mesure.
##
## Aucune règle ici : on lui donne ce que rend D6Profile.tree_view (`montrer`), il se met en page
## SEUL, pour n'importe quel nombre de nœuds par étage — un étage trop large pour la place se
## replie sur plusieurs rangées (petit écran) — et dit quel nœud est choisi (`noeud_choisi`) ou
## appuyé (`noeud_valide`). Chaque nœud est un vrai bouton (doigt, souris, focus du clavier et de
## la manette), sans dessin à lui : tout l'arbre part en UN appel de dessin (jeu/ville/arbre_dessin.gd),
## plus les quelques textes (noms d'étage, numéros d'emplacement).

## Le nœud `id` est choisi : touché, cliqué, ou atteint par le focus.
signal noeud_choisi(id: String)
## Le nœud `id` est appuyé (Entrée, A de la manette, clic, doigt).
signal noeud_valide(id: String)

const Dessin = preload("res://jeu/ville/arbre_dessin.gd")
const IconesArbre = preload("res://jeu/ville/icones_arbre.gd")
const Icones = preload("res://jeu/interface/icones.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")

const GOUTTIERE := 88.0 # à gauche : le nom de l'étage et ce qu'il lui faut
const MARGE := 2.0
const PAS_MIN := 44.0 # largeur minimale donnée à un nœud (cible du doigt)
const PAS_MAX := 84.0
const RAYONS := Vector2(13.5, 19.0) # rayon d'un médaillon : mini, maxi
const RETRAIT := 8.5 # entre le médaillon et le bord de sa place : l'anneau des rangs et le halo y tiennent
const TETE := 4.0 # au-dessus du premier étage (le cercle du nœud choisi y tient)
const HAUT := 8.0 # au-dessus d'un médaillon : l'anneau des rangs
const BAS := 26.0 # sous un médaillon : la fourche des améliorations, les pastilles de rang
const ENTRE := 3.0 # entre deux étages
const BATTEMENT := 3.2 # rad/s : ce qui s'achète bat doucement
const CADENCE := 1.0 / 20.0 # s entre deux dessins de l'arbre qui bat (un battement lent n'en demande pas plus)
const RAYON_NUMERO := 7.0
const ETATS_DE_BOUTON := ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]

## Où va le focus quand on sort de l'arbre par la droite, par le bas (posés par l'onglet).
var voisin_droit: Control
var voisin_bas: Control

var _vue := {}
var _selection := ""
var _places := {} # id du nœud -> emplacement d'action qu'il occupe (0, 1, 2)
var _noeuds := {} # id -> {n, etage, centre, pas}
var _rangees: Array = [] # {etage, premier, ids, pas, haut, y}
var _boutons := {} # id -> Button
var _titres: Array[Label] = []
var _numeros: Array[Label] = []
var _rayon := RAYONS.y
var _hauteur := 0.0 # d'une rangée
var _tronc := 0.0 # abscisse du tronc
var _survol := ""
var _temps := 0.0
var _depuis_le_dessin := 0.0
var _lot := Triangles.new()
var _nu := StyleBoxEmpty.new()

func _ready() -> void:
	resized.connect(_mettre_en_page)
	set_process(false)

# ---------------------------------------------------------------- ce que l'arbre expose

## `vue` : ce que rend D6Profile.tree_view ; `selection` : le nœud choisi ("" : aucun) ; `places` :
## {id du nœud: emplacement d'action} pour les compétences placées.
func montrer(vue: Dictionary, selection: String, places: Dictionary = {}) -> void:
	var avant: Array = _noeuds.keys()
	_vue = vue
	_selection = selection
	_places = places
	_noeuds = {}
	for i in vue.tiers.size():
		for n in vue.tiers[i].nodes:
			_noeuds[String(n.id)] = {"n": n, "etage": i, "centre": Vector2.ZERO, "pas": PAS_MAX}
	if _noeuds.keys() != avant:
		_refaire_les_boutons()
	_mettre_en_page()
	set_process(_bat())
	queue_redraw()

func ids() -> Array:
	return _noeuds.keys()

## Le bouton du nœud `id` (null s'il n'existe pas).
func bouton(id: String) -> Button:
	return _boutons.get(id)

## La place DESSINÉE du nœud `id` (médaillon, anneau des rangs, fourche), dans le repère de l'arbre.
func boite(id: String) -> Rect2:
	var c: Vector2 = _noeuds[id].centre
	var demi := _rayon + Dessin.ANNEAU + Dessin.EP_ANNEAU
	return Rect2(c.x - demi, c.y - demi, 2.0 * demi, demi + _rayon + BAS - 1.0)

## L'état DESSINÉ du nœud `id` : « max », « achetable », « ferme », « acquis » ou « attente ».
func etat_de(id: String) -> String:
	var x: Dictionary = _noeuds[id]
	return _etat(x.n, _vue.tiers[x.etage].open)

## L'état dessiné de chaque amélioration du nœud : « prise », « barree », « offerte », « attente ».
func etats_des_choix(id: String) -> Array:
	var choix: Array = _noeuds[id].n.choices
	var une_prise: bool = choix.any(func(ch: Dictionary) -> bool: return ch.taken)
	return choix.map(func(ch: Dictionary) -> String:
		if ch.taken:
			return "prise"
		return "barree" if une_prise else ("offerte" if ch.canTake else "attente"))

## La largeur où l'arbre de `vue` est à son aise (ses nœuds à `pas` px les uns des autres) :
## au-delà, la place sert mieux au panneau de détail.
static func largeur_aisee(vue: Dictionary, pas: float) -> float:
	var plus := 1
	for etage in vue.get("tiers", []):
		plus = maxi(plus, etage.nodes.size())
	return GOUTTIERE + MARGE + plus * pas

## Nombre de rangées dessinées (un étage replié en compte plusieurs).
func rangees() -> int:
	return _rangees.size()

static func _etat(n: Dictionary, ouvert: bool) -> String:
	if n.rank >= n.maxRank:
		return "max"
	if n.canBuy:
		return "achetable"
	if not ouvert:
		return "ferme"
	return "acquis" if n.rank > 0.0 else "attente"

## Quelque chose bat-il (un nœud à acheter, une amélioration offerte) ? Sinon l'arbre ne se redessine pas.
func _bat() -> bool:
	for id in _noeuds:
		if etat_de(id) == "achetable" or "offerte" in etats_des_choix(id):
			return true
	return false

# ---------------------------------------------------------------- boutons

func _refaire_les_boutons() -> void:
	for b: Button in _boutons.values():
		remove_child(b)
		b.queue_free()
	_boutons = {}
	for id: String in _noeuds:
		_boutons[id] = _bouton(id)

## Un nœud : un bouton nu (le dessin est celui de l'arbre), qui se touche et prend le focus.
func _bouton(id: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.mouse_filter = Control.MOUSE_FILTER_PASS # la molette et le doigt qui glisse défilent aussi par-dessus
	b.tooltip_text = String(_noeuds[id].n.name)
	b.set_meta("cle", "noeud:%s" % id)
	b.set_meta("action", "noeud")
	for etat: String in ETATS_DE_BOUTON:
		b.add_theme_stylebox_override(etat, _nu)
	b.focus_entered.connect(_sur_focus.bind(id))
	b.pressed.connect(_sur_appui.bind(id))
	b.mouse_entered.connect(_survoler.bind(id))
	b.mouse_exited.connect(_survoler.bind(""))
	add_child(b)
	return b

func _sur_focus(id: String) -> void:
	if id != _selection:
		noeud_choisi.emit(id)

func _sur_appui(id: String) -> void:
	if id != _selection:
		noeud_choisi.emit(id)
	noeud_valide.emit(id)

func _survoler(id: String) -> void:
	if id != _survol:
		_survol = id
		queue_redraw()

# ---------------------------------------------------------------- mise en page

## Tout se déduit de la largeur donnée : combien de nœuds de front, leur écart, leur rayon, et la
## hauteur que l'arbre demande (son conteneur défile si elle ne tient pas).
func _mettre_en_page() -> void:
	if _vue.is_empty() or size.x <= 0.0:
		return
	var zone := maxf(PAS_MIN, size.x - GOUTTIERE - MARGE)
	_rangees = _ranger(maxi(1, int(zone / PAS_MIN)))
	var pas_min := PAS_MAX
	for rg: Dictionary in _rangees:
		rg.pas = minf(PAS_MAX, zone / maxf(1.0, rg.ids.size()))
		pas_min = minf(pas_min, rg.pas)
	_rayon = clampf(pas_min / 2.0 - RETRAIT, RAYONS.x, RAYONS.y)
	_hauteur = HAUT + 2.0 * _rayon + BAS
	_tronc = GOUTTIERE + zone / 2.0
	var y := TETE
	for rg: Dictionary in _rangees:
		if rg.premier and y > TETE:
			y += ENTRE
		rg.haut = y
		rg.y = y + HAUT + _rayon
		_placer_la_rangee(rg)
		y += _hauteur
	custom_minimum_size.y = y
	_poser_les_titres()
	_poser_les_numeros()
	_lier_le_focus()
	queue_redraw()

## Les rangées : une par étage, ou plusieurs (de tailles égales) quand l'étage a plus de nœuds
## qu'il n'en tient de front.
func _ranger(capacite: int) -> Array:
	var rangees: Array = []
	for i in _vue.tiers.size():
		var tous: Array = _vue.tiers[i].nodes.map(func(n: Dictionary) -> String: return String(n.id))
		var combien := maxi(1, ceili(tous.size() / float(capacite)))
		var par := maxi(1, ceili(tous.size() / float(combien)))
		for k in combien:
			rangees.append({"etage": i, "premier": k == 0, "ids": tous.slice(k * par, (k + 1) * par), "pas": PAS_MAX, "haut": 0.0, "y": 0.0})
	return rangees

func _placer_la_rangee(rg: Dictionary) -> void:
	var n: int = rg.ids.size()
	for k in n:
		var id: String = rg.ids[k]
		var centre := Vector2(_tronc + (k - (n - 1) / 2.0) * rg.pas, rg.y)
		_noeuds[id].centre = centre
		_noeuds[id].pas = rg.pas
		var b: Button = _boutons[id]
		b.position = Vector2(centre.x - rg.pas / 2.0, rg.haut)
		b.size = Vector2(rg.pas, _hauteur)

## Le focus passe de nœud en nœud : à gauche et à droite dans la rangée, en haut et en bas vers le
## nœud le plus proche de la rangée voisine ; au bout, vers les voisins donnés par l'onglet.
func _lier_le_focus() -> void:
	for j in _rangees.size():
		var ids: Array = _rangees[j].ids
		for k in ids.size():
			var b: Button = _boutons[ids[k]]
			_lier(b, SIDE_LEFT, _boutons[ids[k - 1]] if k > 0 else null)
			_lier(b, SIDE_RIGHT, _boutons[ids[k + 1]] if k < ids.size() - 1 else voisin_droit)
			_lier(b, SIDE_TOP, _plus_proche(j - 1, b))
			_lier(b, SIDE_BOTTOM, _plus_proche(j + 1, b) if j < _rangees.size() - 1 else voisin_bas)

func _lier(b: Button, cote: Side, vers: Control) -> void:
	b.set_focus_neighbor(cote, b.get_path_to(vers) if vers != null and vers.is_inside_tree() else NodePath())

func _plus_proche(rangee: int, de: Button) -> Button:
	var trouve: Button = null
	if rangee < 0 or rangee >= _rangees.size():
		return trouve
	var x := de.position.x + de.size.x / 2.0
	for id: String in _rangees[rangee].ids:
		var autre: Button = _boutons[id]
		if trouve == null or absf(autre.position.x + autre.size.x / 2.0 - x) < absf(trouve.position.x + trouve.size.x / 2.0 - x):
			trouve = autre
	return trouve

# ---------------------------------------------------------------- textes

func _etiquette(liste: Array[Label], rang: int) -> Label:
	while liste.size() <= rang:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		liste.append(l)
	return liste[rang]

## Dans la gouttière, par étage : son nom, et « Ouvert » ou ce qu'il lui faut, avec la progression.
func _poser_les_titres() -> void:
	for l in _titres:
		l.visible = false
	for rg: Dictionary in _rangees:
		if not rg.premier:
			continue
		var etage: Dictionary = _vue.tiers[rg.etage]
		var nom := _etiquette(_titres, 2 * rg.etage)
		nom.theme_type_variation = &"Badge" if etage.open else &"BadgeDoux"
		nom.text = String(etage.name).to_upper()
		nom.position = Vector2(4.0 if etage.open else 16.0, rg.haut + 7.0)
		nom.visible = true
		var besoin := _etiquette(_titres, 2 * rg.etage + 1)
		besoin.theme_type_variation = &"Petit"
		besoin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		besoin.text = "Ouvert" if etage.open else "%s / %s points dépensés" % [D6Js.num_str(minf(_vue.spent, etage.need)), D6Js.num_str(etage.need)]
		besoin.position = Vector2(4.0, rg.haut + 24.0)
		besoin.size = Vector2(GOUTTIERE - 8.0, 0.0)
		besoin.visible = true

## Le numéro d'emplacement (1, 2, 3) des compétences placées, sur leur pastille.
func _poser_les_numeros() -> void:
	for l in _numeros:
		l.visible = false
	var rang := 0
	for id: String in _places:
		if not _noeuds.has(id):
			continue
		var l := _etiquette(_numeros, rang)
		rang += 1
		l.theme_type_variation = &"Repere"
		l.text = str(int(_places[id]) + 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2.ONE * RAYON_NUMERO * 2.0
		l.position = _place_du_numero(id) - l.size / 2.0
		l.visible = true

func _place_du_numero(id: String) -> Vector2:
	return _noeuds[id].centre + Vector2(_rayon, -_rayon) * 0.86

# ---------------------------------------------------------------- dessin

## Seulement quand quelque chose bat (`_bat`), et pas plus souvent que CADENCE : le lot entier est
## refait à chaque dessin.
func _process(delta: float) -> void:
	_temps += delta
	_depuis_le_dessin += delta
	if _depuis_le_dessin >= CADENCE and is_visible_in_tree():
		_depuis_le_dessin = 0.0
		queue_redraw()

func _draw() -> void:
	if _rangees.is_empty():
		return
	var pouls := 0.5 + 0.5 * sin(_temps * BATTEMENT)
	_dessiner_les_etages()
	for id: String in _noeuds:
		if id != _selection:
			_dessiner_le_noeud(id, pouls)
	if _noeuds.has(_selection):
		_dessiner_le_noeud(_selection, pouls) # en dernier : son cercle passe devant ses voisins
	_lot.tracer(self)

## Bandes, tronc (en or jusqu'où l'arbre est ouvert), branches, entrées d'étage, cadenas.
func _dessiner_les_etages() -> void:
	for j in _rangees.size():
		var rg: Dictionary = _rangees[j]
		var ouvert: bool = _vue.tiers[rg.etage].open
		Dessin.bande(_lot, Rect2(0.0, rg.haut, size.x, _hauteur), ouvert)
		if j > 0:
			Dessin.tronc(_lot, Vector2(_tronc, _rangees[j - 1].y), Vector2(_tronc, rg.y), _part_du_tronc(_rangees[j - 1], rg))
	for rg: Dictionary in _rangees:
		var ouvert: bool = _vue.tiers[rg.etage].open
		var demi: float = (rg.ids.size() - 1) / 2.0 * rg.pas
		Dessin.branche(_lot, Vector2(_tronc - demi, rg.y), Vector2(_tronc + demi, rg.y), ouvert)
		if rg.premier and rg.etage > 0:
			Dessin.entree(_lot, Vector2(_tronc, rg.haut), ouvert)
		if rg.premier and not ouvert:
			Dessin.cadenas(_lot, Vector2(9.0, rg.haut + 15.0))

## La part d'or du morceau de tronc qui mène d'une rangée à la suivante : plein vers un étage
## ouvert ; vers le premier étage fermé, la part des points déjà dépensés ; au-delà, rien.
func _part_du_tronc(avant: Dictionary, apres: Dictionary) -> float:
	var etage: Dictionary = _vue.tiers[apres.etage]
	if apres.etage == avant.etage or etage.open:
		return 1.0
	if not _vue.tiers[avant.etage].open or etage.need <= 0.0:
		return 0.0
	return clampf(_vue.spent / etage.need, 0.0, 1.0)

func _dessiner_le_noeud(id: String, pouls: float) -> void:
	var x: Dictionary = _noeuds[id]
	var n: Dictionary = x.n
	var d := {
		"sorte": n.kind, "icone": _icone(n), "etat": etat_de(id), "acquis": n.rank > 0.0, "rang": n.rank, "rangs": n.maxRank,
		"choisi": id == _selection, "survol": id == _survol,
	}
	if not n.choices.is_empty():
		Dessin.fourche(_lot, x.centre, _rayon, etats_des_choix(id), pouls)
	Dessin.medaillon(_lot, x.centre, _rayon, d, pouls)
	if _places.has(id):
		Dessin.emplacement(_lot, _place_du_numero(id), RAYON_NUMERO)

## Le pictogramme d'un nœud : celui que rendent les règles (le bouton en jeu) ; un passif n'en a
## pas, il prend celui que son texte évoque.
func _icone(n: Dictionary) -> String:
	if Icones.connue(n.icon):
		return n.icon
	return IconesArbre.passif(String(n.text))
