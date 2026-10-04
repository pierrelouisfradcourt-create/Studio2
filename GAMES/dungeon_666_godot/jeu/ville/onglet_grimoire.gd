extends "res://jeu/ville/onglet.gd"
## Grimoire (combat V3, étape 1) : les TROIS emplacements d'action de la classe équipée, et les
## compétences et gadgets qu'on peut y placer (placé, à placer, à débloquer). Le Super de la
## classe est rappelé : il ne se choisit pas, il vient avec la classe et se lance en gardant
## l'attaque appuyée. Aucune règle ici : D6Profile.slot_choices dit ce qui se place,
## l'opération `select_slot` place (un échange si l'action est déjà ailleurs) ou vide.

## Le texte nomme ce qui est RÉELLEMENT équipé (lu dans le profil), jamais une action en dur.
const NOTE := "%s — emplacements : %s. Une compétence se recharge, un gadget a des charges par section."
const VIDE := "vide"
const GENRES := {"skill": "skills", "gadget": "gadgets"}
const SURTITRES := {"skill": "Compétence", "gadget": "Gadget"}

@onready var _note: Label = $Note
@onready var _emplacements: GridContainer = $Emplacements
@onready var _competences: GridContainer = $Competences
@onready var _gadgets: GridContainer = $Gadgets
@onready var _super: GridContainer = $Super

func _dessiner() -> void:
	var c: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	var choix: Array = D6Profile.slot_choices(app.profil, app.contenu)
	var places: Array = app.profil.loadout.slots
	var noms: Array = []
	for i in places.size():
		noms.append("%d · %s" % [i + 1, _nom_action(choix, places[i])])
	_note.text = NOTE % [c.name, ", ".join(noms)]
	_lister_emplacements(choix, places)
	_lister(_competences, choix, places, "skill")
	_lister(_gadgets, choix, places, "gadget")
	_vider(_super)
	var s = app.contenu.supers.get(c.super)
	if s is Dictionary:
		_carte(_super, {"surtitre": "Super · %s" % c.name, "titre": s.name, "lignes": [s.get("text", ""), "Jauge pleine : garde l'attaque appuyée."], "etat": "equipe", "badge": "Lié à la classe"})

func _nom_action(choix: Array, id) -> String:
	for x in choix:
		if x.id == id:
			return String(x.name)
	return VIDE

## Les trois emplacements : ce qu'ils portent, et un bouton pour les vider.
func _lister_emplacements(choix: Array, places: Array) -> void:
	_vider(_emplacements)
	for i in places.size():
		var cle := "slots:%d" % i
		var d := {"surtitre": "Emplacement %d" % (i + 1), "titre": "Vide" if places[i] == null else _nom_action(choix, places[i]), "refus": _raison(cle)}
		if places[i] == null:
			d.etat = "vide"
		else:
			d.etat = "equipe"
			d.boutons = [{"nom": "vider", "texte": "Vider", "genre": "discret", "cle": cle}]
		_carte(_emplacements, d).action.connect(_sur_emplacement.bind(i))

## Les actions d'une sorte : placée (dans quel emplacement), à placer (un bouton par emplacement),
## ou à débloquer.
func _lister(grille: GridContainer, choix: Array, places: Array, sorte: String) -> void:
	_vider(grille)
	for x in choix:
		if x.kind != sorte:
			continue
		var genre: String = GENRES[sorte]
		var cle := "%s:%s" % [genre, x.id]
		var d := {"surtitre": SURTITRES[sorte], "titre": x.name, "lignes": [x.text], "refus": _raison(cle)}
		var place: int = places.find(x.id)
		if not x.unlocked:
			_pied_achat(d, cle, "debloquer", "Débloquer", x.cost)
			d.etat = "verrouille"
		else:
			if place >= 0:
				d.etat = "equipe"
				d.badge = "● Emplacement %d" % (place + 1)
			d.boutons = []
			for i in places.size():
				d.boutons.append({"nom": "slot%d" % i, "texte": "→ %d" % (i + 1), "genre": "" if i == place else "principal", "inactif": i == place, "cle": cle})
		_carte(grille, d).action.connect(_sur_action.bind(genre, x.id))

func _sur_action(nom: String, genre: String, id: String) -> void:
	var cle := "%s:%s" % [genre, id]
	if nom.begins_with("slot"):
		operation_demandee.emit(cle, "select_slot", [float(nom.trim_prefix("slot").to_int()), id])
	elif nom == "debloquer":
		operation_demandee.emit(cle, "unlock", [genre, id])

func _sur_emplacement(nom: String, index: int) -> void:
	if nom == "vider":
		operation_demandee.emit("slots:%d" % index, "select_slot", [float(index), null])
