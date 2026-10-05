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
##
## ARBRE DE COMPÉTENCES (combat V3, étape 3 ; affichage volontairement simple) : sous les
## emplacements, le niveau de la classe, sa barre d'expérience, ses points, puis l'arbre en liste
## par étage — une carte par nœud : rang, texte du rang actuel et du suivant, bouton « + » (grisé
## avec sa raison), les deux améliorations exclusives. « Tout rendre » se confirme en deux appuis.
## Tout est LU dans D6Profile.tree_view ; opérations tree_buy, tree_choose, tree_respec.

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
const CLE_RENDRE := "arbre:rendre"
const Grille = preload("res://jeu/ville/grille.gd")
const Accords = preload("res://jeu/theme/accords.gd")
const SORTES := {"skill": "Compétence", "passive": "Passif", "move": "Déplacement", "ultimate": "Ultime"}
const VERROU := "À débloquer dans l'arbre"
const LARGEUR_NOEUD := 250.0

@onready var _note: Label = $Note
@onready var _arc: Control = %Arc
@onready var _aide: Label = %Aide
@onready var _lignes: Array = [%Choix1, %Choix2, %Choix3]
@onready var _vidages: Array = [%Vider1, %Vider2, %Vider3]
@onready var _actions: GridContainer = $Actions
@onready var _super: GridContainer = $Super
@onready var _niveau: Label = %NiveauTexte
@onready var _experience: ProgressBar = %Experience
@onready var _experience_texte: Label = %ExperienceTexte
@onready var _points: Label = %Points
@onready var _etages: VBoxContainer = %Etages
@onready var _rendre: Button = %Rendre
@onready var _refus_rendre: Label = %RefusRendre

var _action := "" # la compétence touchée en premier ("" : aucune)
var _emplacement := -1 # l'emplacement touché en premier (-1 : aucun)
var _rendre_confirme := false # « Tout rendre » attend son second appui

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
	_rendre.set_meta("cle", CLE_RENDRE)
	_rendre.set_meta("action", "rendre")
	_rendre.pressed.connect(_sur_rendre)

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
	_dessiner_arbre()
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

## Les compétences de la classe : placée (dans quel emplacement), à placer, ou à débloquer (dans l'arbre).
func _lister(choix: Array, places: Array) -> void:
	_vider(_actions)
	for x in choix:
		var genre: String = GENRES[x.kind]
		var cle := "%s:%s" % [genre, x.id]
		var d := {"surtitre": "%s · rang %s" % [SURTITRES[x.kind], D6Js.num_str(x.rank)], "titre": x.name, "lignes": [x.text], "refus": _raison(cle), "picto": _picto(x.icon, x.unlocked)}
		var place: int = places.find(x.id)
		if not x.unlocked:
			d.boutons = [{"nom": "verrou", "texte": VERROU, "inactif": true, "cle": cle}]
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
		_rendre_confirme = false

# ---------------------------------------------------------------- arbre de compétences

## Niveau, expérience, points, puis l'arbre de la classe portée, étage par étage.
func _dessiner_arbre() -> void:
	var classe: String = app.profil.loadout.classId
	var v: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	var au_sommet: bool = v.level >= v.maxLevel
	_niveau.text = "Niveau %s / %s" % [D6Js.num_str(v.level), D6Js.num_str(v.maxLevel)]
	_experience.max_value = 1.0 if au_sommet else v.xpNext
	_experience.value = 1.0 if au_sommet else v.xp
	_experience_texte.text = "Niveau maximum" if au_sommet else "%s / %s d'expérience" % [D6Js.num_str(v.xp), D6Js.num_str(v.xpNext)]
	_points.text = "● %s à dépenser" % Accords.compte(v.points, "point", "points") if v.points > 0.0 else "Aucun point à dépenser"
	_vider(_etages)
	var pris := false
	for etage in v.tiers:
		_dessiner_etage(etage, classe, v.choiceRank)
		for n in etage.nodes:
			pris = pris or n.choices.any(func(ch): return ch.taken)
	var texte := "Confirmer : tout rendre (%s or)" if _rendre_confirme else "Tout rendre (%s or)"
	_rendre.text = texte % D6Js.num_str(v.respecCost)
	_rendre.theme_type_variation = &"BoutonDanger" if _rendre_confirme else &"BoutonDiscret"
	_rendre.disabled = v.spent <= 0.0 and not pris
	_refus_rendre.text = _raison(CLE_RENDRE)

## Un étage : son titre (ouvert, ou ce qu'il faut dépenser avant) et une carte par nœud.
func _dessiner_etage(etage: Dictionary, classe: String, rang_du_choix: float) -> void:
	var titre := Label.new()
	titre.theme_type_variation = &"TexteDoux"
	titre.text = "Étage %s" % etage.name if etage.open else "Étage %s — s'ouvre après %s points dépensés" % [etage.name, D6Js.num_str(etage.need)]
	_etages.add_child(titre)
	var grille := GridContainer.new()
	grille.set_script(Grille)
	grille.largeur_mini = LARGEUR_NOEUD
	grille.colonnes_max = 3
	grille.add_theme_constant_override("h_separation", 10)
	grille.add_theme_constant_override("v_separation", 10)
	_etages.add_child(grille)
	for n in etage.nodes:
		_carte_noeud(grille, n, classe, rang_du_choix)

## La carte d'un nœud : rang, texte du rang actuel et du suivant, « + », améliorations exclusives.
func _carte_noeud(grille: Node, n: Dictionary, classe: String, rang_du_choix: float) -> void:
	var cle := "arbre:%s" % n.id
	var lignes: Array = []
	if n.now != "":
		lignes.append(n.now)
	if n.next != "":
		lignes.append({"texte": "Suivant — %s" % n.next, "genre": "Affixe"})
	var boutons: Array = [{"nom": "plus", "texte": "+", "genre": "principal" if n.canBuy else "", "inactif": not n.canBuy, "cle": cle}]
	for ch in n.choices:
		lignes.append({"texte": "%s %s : %s" % ["●" if ch.taken else "◇", ch.name, ch.text], "genre": "Pouvoir" if ch.taken else "TexteDoux"})
		if n.rank >= rang_du_choix and not ch.taken:
			boutons.append({"nom": "choix:%s" % ch.id, "texte": ch.name, "genre": "principal" if ch.canTake else "", "inactif": not ch.canTake, "cle": "%s:%s" % [cle, ch.id]})
	var d := {
		"surtitre": "%s · rang %s / %s" % [SORTES[n.kind], D6Js.num_str(n.rank), D6Js.num_str(n.maxRank)], "titre": n.name, "lignes": lignes,
		"etat": "equipe" if n.rank > 0.0 else "", "badge": "Offert" if n.free and n.rank == 1.0 else "", "boutons": boutons,
		"refus": _raison(cle) if _raison(cle) != "" else _dire(n.reason),
	}
	if n.icon != "":
		d.picto = _picto(n.icon, n.rank > 0.0)
	_carte(grille, d).action.connect(_sur_noeud.bind(classe, String(n.id)))

## Une raison telle qu'on l'affiche : première lettre en capitale.
func _dire(raison: String) -> String:
	return raison.left(1).to_upper() + raison.substr(1)

func _sur_noeud(nom: String, classe: String, id: String) -> void:
	var cle := "arbre:%s" % id
	_rendre_confirme = false
	if nom == "plus":
		operation_demandee.emit(cle, "tree_buy", [classe, id])
	elif nom.begins_with("choix:"):
		operation_demandee.emit(cle, "tree_choose", [classe, id, nom.trim_prefix("choix:")])

## « Tout rendre » : un premier appui demande confirmation (c'est payant), le second rend les points.
func _sur_rendre() -> void:
	if not _rendre_confirme:
		_rendre_confirme = true
		dessin_demande.emit()
		return
	_rendre_confirme = false
	operation_demandee.emit(CLE_RENDRE, "tree_respec", [String(app.profil.loadout.classId)])
