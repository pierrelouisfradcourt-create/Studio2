extends "res://jeu/ville/onglet.gd"
## Grimoire (combat V3) : en haut, les TROIS emplacements d'action dessinés comme en jeu (le même
## arc autour de l'attaque, les mêmes pictogrammes : jeu/ville/arc_emplacements.gd) et leur
## légende ; dessous, les compétences de la classe. On touche une compétence PUIS un emplacement
## (ou l'inverse) : elle y est placée ; une compétence déjà placée est marquée. L'ultime de la
## classe est rappelé : il ne se choisit pas, il se lance en gardant l'attaque appuyée. Le
## DÉPLACEMENT de la classe (dash, saut, roulade) l'est aussi : son bouton, son nom, ce qu'il fait.
## Aucune règle ici : D6Profile.slot_choices dit ce qui se place, l'opération `select_slot` place
## (un échange si l'action est déjà ailleurs) ou vide. Ce que le joueur a touché en premier (une
## compétence, un emplacement) n'est qu'un état d'ÉCRAN : rien n'est écrit tant qu'il n'a pas
## touché le second.

const Commande = preload("res://jeu/interface/commande.gd")

## Le texte nomme ce qui est RÉELLEMENT équipé (lu dans le profil), jamais une action en dur.
const NOTE := "%s — emplacements : %s. En jeu, ce sont les trois boutons autour de l'attaque."
const VIDE := "vide"
const GENRES := {"skill": "skills", "gadget": "gadgets"}
## Une compétence se recharge avec le temps ; l'autre sorte (les anciens gadgets) a des charges.
const SURTITRES := {"skill": "Se recharge", "gadget": "À charges"}
const AIDES := {
	"rien": "Touche une compétence, puis l'emplacement où la placer (ou l'inverse).",
	"action": "« %s » : touche maintenant l'emplacement où la placer.",
	"emplacement": "Emplacement %d : touche maintenant la compétence à y placer.",
}
const RAYON_PICTO := 15.0

@onready var _note: Label = $Note
@onready var _arc: Control = %Arc
@onready var _aide: Label = %Aide
@onready var _lignes: Array = [%Choix1, %Choix2, %Choix3]
@onready var _vidages: Array = [%Vider1, %Vider2, %Vider3]
@onready var _actions: GridContainer = $Actions
@onready var _super: GridContainer = $Super

var _action := "" # la compétence touchée en premier ("" : aucune)
var _emplacement := -1 # l'emplacement touché en premier (-1 : aucun)

func _ready() -> void:
	_arc.emplacement_touche.connect(_sur_emplacement)
	for i in _lignes.size():
		for b: Button in [_lignes[i], _vidages[i]]:
			b.set_meta("cle", "slots:%d" % i)
		_lignes[i].set_meta("action", "ligne")
		_vidages[i].set_meta("action", "vider")
		_lignes[i].pressed.connect(_sur_emplacement.bind(i))
		_vidages[i].pressed.connect(_sur_vider.bind(i))
	visibility_changed.connect(_oublier)

func _dessiner() -> void:
	var c: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	var choix: Array = D6Profile.slot_choices(app.profil, app.contenu)
	var places: Array = app.profil.loadout.slots
	if _trouver(choix, _action).is_empty():
		_action = "" # la classe a changé : cette compétence n'est plus proposée
	var noms: Array = []
	for i in places.size():
		noms.append("%d · %s" % [i + 1, _trouver(choix, places[i]).get("name", VIDE)])
	_note.text = NOTE % [c.name, ", ".join(noms)]
	_ecrire_aide(choix)
	_montrer_emplacements(choix, places)
	_lister(choix, places)
	_vider(_super)
	var geste = app.contenu.moves.get(c.get("move"))
	if geste is Dictionary:
		_carte(_super, {"surtitre": "Déplacement · %s" % c.name, "titre": geste.name, "lignes": [geste.text], "etat": "equipe", "badge": "Lié à la classe", "picto": _picto(String(geste.get("icon", "dash")), true)})
	var s = app.contenu.supers.get(c.super)
	if s is Dictionary:
		_carte(_super, {"surtitre": "Ultime · %s" % c.name, "titre": s.name, "lignes": [s.get("text", ""), "Jauge pleine : garde l'attaque appuyée."], "etat": "equipe", "badge": "Lié à la classe", "picto": _picto(String(s.get("icon", "super")), true)})

func _trouver(choix: Array, id) -> Dictionary:
	for x in choix:
		if x.id == id:
			return x
	return {}

func _ecrire_aide(choix: Array) -> void:
	if _action != "":
		_aide.text = AIDES.action % _trouver(choix, _action).name
	elif _emplacement >= 0:
		_aide.text = AIDES.emplacement % (_emplacement + 1)
	else:
		_aide.text = AIDES.rien

## L'arc (les boutons du jeu) et sa légende : ce que porte chaque emplacement, lequel est choisi,
## et « Vider » pour un emplacement rempli.
func _montrer_emplacements(choix: Array, places: Array) -> void:
	var pictos: Array = []
	for i in _lignes.size():
		var x: Dictionary = _trouver(choix, places[i]) if i < places.size() else {}
		pictos.append(String(x.get("icon", "")))
		_lignes[i].text = "%d · %s" % [i + 1, x.get("name", "Vide")]
		_lignes[i].set_pressed_no_signal(i == _emplacement)
		_vidages[i].disabled = x.is_empty()
		_vidages[i].modulate.a = Style.OPACITE_GRISE if x.is_empty() else 1.0
	_arc.montrer(pictos, _emplacement)

## Les compétences de la classe : placée (dans quel emplacement), à placer, ou à débloquer.
func _lister(choix: Array, places: Array) -> void:
	_vider(_actions)
	for x in choix:
		var genre: String = GENRES[x.kind]
		var cle := "%s:%s" % [genre, x.id]
		var d := {"surtitre": SURTITRES[x.kind], "titre": x.name, "lignes": [x.text], "refus": _raison(cle), "picto": _picto(x.icon, x.unlocked)}
		var place: int = places.find(x.id)
		if not x.unlocked:
			_pied_achat(d, cle, "debloquer", "Débloquer", x.cost)
			d.etat = "verrouille"
		else:
			if place >= 0:
				d.etat = "equipe"
				d.badge = "● Emplacement %d" % (place + 1)
			d.boutons = [_bouton_de_placement(x, place, cle)]
		_carte(_actions, d).action.connect(_sur_action.bind(genre, x.id))

## Le bouton d'une compétence possédée, selon ce qui a été touché en premier.
func _bouton_de_placement(x: Dictionary, place: int, cle: String) -> Dictionary:
	if _emplacement >= 0:
		if place == _emplacement:
			return {"nom": "", "texte": "Déjà dans l'emplacement %d" % (place + 1), "inactif": true, "cle": cle}
		return {"nom": "placer", "texte": "Placer dans l'emplacement %d" % (_emplacement + 1), "genre": "principal", "cle": cle}
	if _action == x.id:
		return {"nom": "choisir", "texte": "Choisie — touche un emplacement", "genre": "principal", "cle": cle}
	return {"nom": "choisir", "texte": "Choisir", "cle": cle}

## Le pictogramme de l'action, celui de son bouton en jeu.
func _picto(icone: String, possedee: bool) -> Control:
	var c: Control = Commande.new()
	c.rayon = RAYON_PICTO
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.modulate.a = 1.0 if possedee else Style.OPACITE_GRISE
	c.montrer({"pret": 1.0, "icone": icone})
	return c

# ---------------------------------------------------------------- ce que le joueur touche

func _sur_action(nom: String, genre: String, id: String) -> void:
	var cle := "%s:%s" % [genre, id]
	match nom:
		"debloquer":
			operation_demandee.emit(cle, "unlock", [genre, id])
		"placer":
			_placer(cle, _emplacement, id)
		"choisir":
			_action = "" if _action == id else id
			dessin_demande.emit()

## Un emplacement est touché (sur l'arc ou dans la légende) : une compétence attendait, elle y va ;
## sinon c'est lui qui attend une compétence (le toucher de nouveau l'oublie).
func _sur_emplacement(index: int) -> void:
	if _action != "":
		_placer("%s:%s" % [_genre_de(_action), _action], index, _action)
		return
	_emplacement = -1 if _emplacement == index else index
	dessin_demande.emit()

func _sur_vider(index: int) -> void:
	_placer("slots:%d" % index, index, null)

func _placer(cle: String, index: int, id) -> void:
	_action = ""
	_emplacement = -1
	operation_demandee.emit(cle, "select_slot", [float(index), id])

func _genre_de(id: String) -> String:
	return "skills" if app.contenu.skills.has(id) else "gadgets"

## L'onglet quitté puis rouvert ne garde pas un choix à moitié fait.
func _oublier() -> void:
	if not is_visible_in_tree():
		_action = ""
		_emplacement = -1
