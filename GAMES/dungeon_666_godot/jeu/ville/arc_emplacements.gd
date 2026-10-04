extends Control
## Les TROIS emplacements d'action, dessinés comme en jeu : le même arc autour du bouton d'attaque
## (les places viennent de la disposition tactile, jeu/interface/disposition.gd), les mêmes boutons
## (jeu/interface/commande.gd), les mêmes pictogrammes. L'attaque et le dash sont là en filigrane,
## pour qu'on reconnaisse l'écran de jeu ; seuls les trois emplacements se touchent.
## Aucune règle ici : on lui dit quoi montrer (`montrer`), il signale l'emplacement touché.

signal emplacement_touche(index: int)

const Commande = preload("res://jeu/interface/commande.gd")
const Disposition = preload("res://jeu/interface/disposition.gd")

const ECHELLE := 0.8 # taille des boutons par rapport au jeu
const CADRE := Vector2(480.0, 400.0) # écran fictif où la disposition est calculée
const MARGE := 6.0 # autour du groupe, anneau des boutons compris
const FILIGRANE := 0.3 # opacité de l'attaque et du dash (ils ne se règlent pas ici)
const EMPLACEMENTS := ["skill1", "skill2", "skill3"]
const DECOR := {"attack": {"pret": 1.0, "jauge": 0.0, "icone": "attack"}, "dash": {"pret": 1.0, "icone": "dash"}}

var _places := {} # id -> {centre, r}, repère du groupe (coin haut-gauche = 0, 0)
var _groupe := Vector2.ZERO # taille du groupe
var _dessins := {} # id -> la commande dessinée
var _boutons: Array[Button] = []

func _ready() -> void:
	_mesurer()
	for id in DECOR:
		var decor := _commande(id)
		decor.modulate.a = FILIGRANE
		add_child(decor)
		decor.montrer(DECOR[id])
	for i in EMPLACEMENTS.size():
		_boutons.append(_bouton(i))
	custom_minimum_size = _groupe
	resized.connect(_placer)
	_placer()

## `actions` : pour chaque emplacement, le pictogramme de son action ("" : vide) ; `choisi` :
## l'emplacement choisi (son anneau bat), ou -1.
func montrer(actions: Array, choisi: int) -> void:
	for i in EMPLACEMENTS.size():
		var icone: String = actions[i] if i < actions.size() else ""
		_dessins[EMPLACEMENTS[i]].montrer({"pret": 0.0, "vide": true, "icone": ""} if icone == "" else {"pret": 1.0, "icone": icone})
		_dessins[EMPLACEMENTS[i]].designer(i == choisi)
		_boutons[i].set_pressed_no_signal(i == choisi)

## Le bouton de l'emplacement `index` (pour les essais et le focus).
func bouton(index: int) -> Button:
	return _boutons[index]

## Les places du jeu, réduites, ramenées à un groupe dont le coin haut-gauche est l'origine.
func _mesurer() -> void:
	var ui: Dictionary = Disposition.calculer(CADRE, Vector4.ZERO, ECHELLE)
	var boite := Rect2()
	for b in ui.buttons:
		var cercle := Rect2(b.x - b.r, b.y - b.r, 2.0 * b.r, 2.0 * b.r).grow(Commande.MARGE + MARGE)
		boite = cercle if boite.size == Vector2.ZERO else boite.merge(cercle)
	for b in ui.buttons:
		_places[b.id] = {"centre": Vector2(b.x, b.y) - boite.position, "r": b.r}
	_groupe = boite.size

func _commande(id: String) -> Control:
	var c: Control = Commande.new()
	c.id = id
	c.rayon = _places[id].r
	_dessins[id] = c
	return c

## Un emplacement : un vrai bouton (doigt, souris, focus du clavier et de la manette), son dessin
## et son numéro.
func _bouton(index: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.toggle_mode = true
	b.mouse_filter = Control.MOUSE_FILTER_PASS # la molette et le doigt qui glisse défilent aussi par-dessus
	b.tooltip_text = "Emplacement %d" % (index + 1)
	b.set_meta("cle", "slots:%d" % index)
	b.set_meta("action", "emplacement")
	b.pressed.connect(func() -> void: emplacement_touche.emit(index))
	b.add_child(_commande(EMPLACEMENTS[index]))
	var numero := Label.new()
	numero.text = str(index + 1)
	numero.theme_type_variation = &"Badge"
	numero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(numero)
	add_child(b)
	return b

## Le groupe est centré dans la place donnée ; chaque bouton prend le carré de son dessin.
func _placer() -> void:
	var origine := ((size - _groupe) / 2.0).max(Vector2.ZERO)
	for id in _dessins:
		var dessin: Control = _dessins[id]
		var cote: Vector2 = dessin.custom_minimum_size
		var hote: Control = dessin.get_parent() if id in EMPLACEMENTS else dessin
		hote.position = origine + _places[id].centre - cote / 2.0
		hote.size = cote
		if hote != dessin:
			dessin.position = Vector2.ZERO
			dessin.size = cote
