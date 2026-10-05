extends "res://jeu/ville/onglet.gd"
## GRIMOIRE : l'écran de l'ARBRE DE COMPÉTENCES de la classe portée (combat V3). Trois colonnes,
## qui tiennent sans défiler en 1280 × 720 :
##   à gauche   les points à dépenser (gros), le niveau, la barre d'expérience, et les TROIS
##              emplacements d'action dessinés comme en jeu (jeu/ville/arc_emplacements.gd) ;
##   au milieu  l'arbre dessiné (jeu/ville/arbre.gd) : étages en bandes le long du tronc, un
##              médaillon par nœud, « Tout rendre » à son pied ; lui seul défile, de haut en bas,
##              quand la fenêtre est basse (téléphone) ;
##   en tête    une note d'une ligne : la classe et ce que portent ses trois emplacements ;
##   à droite   le panneau de détail (jeu/ville/panneau_noeud.gd) du nœud choisi — ou de
##              l'emplacement touché sur l'arc.
## En portrait (toléré), les trois blocs s'empilent et c'est la page de la Ville qui défile.
##
## Aucune règle ici : tout est LU dans D6Profile.tree_view et D6Profile.slot_choices ; chaque geste
## demande une opération (tree_buy, tree_choose, tree_respec, select_slot) par `operation_demandee`.
## Le nœud choisi, l'emplacement choisi, une confirmation en attente ne sont que des états d'ÉCRAN :
## rien n'est écrit tant que l'opération n'est pas demandée, et tout est oublié en quittant l'onglet.
## Une amélioration exclusive et « Tout rendre » se CONFIRMENT : un second appui sur le même bouton.

const Accords = preload("res://jeu/theme/accords.gd")

const CLE_RENDRE := "arbre:rendre"
## Le texte nomme ce qui est RÉELLEMENT équipé (lu dans le profil), jamais une action en dur.
const NOTE := "%s — emplacements : %s. En jeu, ce sont les trois boutons autour de l'attaque."
const VIDE := "vide"
const SORTES := {"skill": "Compétence", "passive": "Passif", "move": "Déplacement", "ultimate": "Ultime"}
const A_CHARGES := "Compétence à charges"
const LARGEUR_ETROITE := 640.0 # en deçà (portrait), les trois blocs s'empilent
const HAUTEUR_AISEE := 300.0 # en deçà (téléphone), la note d'en-tête cède sa ligne à l'arbre
const PANNEAU := Vector2(276.0, 360.0) # largeur du panneau de détail : mini, maxi
const PAS_AISE := 58.0 # écart entre deux nœuds où l'arbre est à son aise : au-delà, la place va au panneau
const AVIS_RENDRE := "Tous les points reviennent ; les améliorations choisies sont effacées."

@onready var _note: Label = $Note
@onready var _corps: BoxContainer = %Corps
@onready var _pastille: Control = %PastillePoints
@onready var _points: Label = %Points
@onready var _niveau: Label = %NiveauTexte
@onready var _experience: Control = %Experience
@onready var _experience_texte: Label = %ExperienceTexte
@onready var _arc: Control = %Arc
@onready var _defile: ScrollContainer = %Defile
@onready var _arbre: Control = %Arbre
@onready var _rendre: Button = %Rendre
@onready var _refus_rendre: Label = %RefusRendre
@onready var _panneau_defile: ScrollContainer = %PanneauDefile
@onready var _cadre: PanelContainer = %Cadre
@onready var _infos: VBoxContainer = %Infos
@onready var _panneau: VBoxContainer = %Panneau

## Banc d'essai : une vue d'arbre donnée à la place de celle des règles (arbre factice, plus chargé).
var vue_forcee := {}

var _vue := {} # ce que rend tree_view pour la classe portée
var _actions: Array = [] # ce que rend slot_choices
var _selection := "" # le nœud choisi
var _emplacement := -1 # l'emplacement choisi sur l'arc (-1 : aucun) ; il attend une compétence
var _devant := "noeud" # ce que montre le panneau : « noeud » ou « emplacement »
var _rendre_confirme := false # « Tout rendre » attend son second appui
var _a_confirmer := "" # « nœud:amélioration » qui attend son second appui
var _place := Vector2.ZERO # la place offerte par la Ville (sa zone de défilement)
var _au_clavier := false # le dernier geste vient du clavier ou de la manette (ni doigt, ni souris)

func _ready() -> void:
	_arc.emplacement_touche.connect(_sur_emplacement)
	_arbre.noeud_choisi.connect(_sur_noeud_choisi)
	_arbre.noeud_valide.connect(_sur_noeud_valide)
	_arbre.voisin_droit = _panneau.bouton_acheter()
	_arbre.voisin_bas = _rendre
	_panneau.achat_demande.connect(_sur_achat)
	_panneau.choix_demande.connect(_sur_choix)
	_panneau.placement_demande.connect(_sur_placement)
	_panneau.vidage_demande.connect(_sur_vidage)
	_rendre.set_meta("cle", CLE_RENDRE)
	_rendre.set_meta("action", "rendre")
	_rendre.pressed.connect(_sur_rendre)
	visibility_changed.connect(_oublier)
	resized.connect(_adapter)
	_adapter()

# ---------------------------------------------------------------- ce que l'onglet expose

## L'arbre dessiné et le panneau de détail (pour les bancs et les essais).
func arbre() -> Control:
	return _arbre

func panneau() -> Control:
	return _panneau

## Choisit le nœud `id` comme le ferait un toucher : le panneau le montre.
func selectionner(id: String) -> void:
	_sur_noeud_choisi(id)

func selection() -> String:
	return _selection

## Le bouton de ce que montre le panneau : l'emplacement choisi sur l'arc, sinon le nœud choisi.
func repli_du_focus() -> Control:
	if _devant == "emplacement" and _emplacement >= 0:
		return _arc.bouton(_emplacement)
	return _arbre.bouton(_selection)

# ---------------------------------------------------------------- dessin

func _dessiner() -> void:
	var classe: String = app.profil.loadout.classId
	_vue = vue_forcee if not vue_forcee.is_empty() else D6Profile.tree_view(app.profil, app.contenu, classe)
	_actions = D6Profile.slot_choices(app.profil, app.contenu)
	if _noeud(_selection).is_empty():
		_selection = _premier_noeud()
	_ecrire_les_infos()
	_montrer_les_emplacements()
	_partager_la_largeur()
	_arbre.montrer(_vue, "" if _devant == "emplacement" else _selection, _places())
	_montrer_le_panneau(classe)
	_ecrire_rendre()

## Le nœud `id` tel que le rend tree_view ({} s'il n'existe pas).
func _noeud(id: String) -> Dictionary:
	for etage in _vue.get("tiers", []):
		for n in etage.nodes:
			if String(n.id) == id:
				return n
	return {}

## À l'ouverture : le premier nœud où un point peut être dépensé ; à défaut, le premier de l'arbre.
func _premier_noeud() -> String:
	var premier := ""
	for etage in _vue.tiers:
		for n in etage.nodes:
			if n.canBuy:
				return String(n.id)
			if premier == "":
				premier = String(n.id)
	return premier

## L'action d'emplacement (slot_choices) que porte un nœud de compétence, {} sinon. tree_view ne
## donne pas l'identifiant de l'action : c'est celui du nœud (les données les nomment pareil), et
## à défaut celle qui porte le même nom.
func _action_de(n: Dictionary) -> Dictionary:
	if n.is_empty() or n.kind != "skill":
		return {}
	for x in _actions:
		if x.id == n.id:
			return x
	for x in _actions:
		if x.name == n.name:
			return x
	return {}

func _action(id) -> Dictionary:
	for x in _actions:
		if x.id == id:
			return x
	return {}

## {id du nœud: emplacement} des compétences placées (l'arbre y pose une pastille numérotée).
func _places() -> Dictionary:
	var places := {}
	var portes: Array = app.profil.loadout.slots
	for etage in _vue.tiers:
		for n in etage.nodes:
			var x := _action_de(n)
			var rang: int = portes.find(x.id) if not x.is_empty() else -1
			if rang >= 0:
				places[String(n.id)] = rang
	return places

func _ecrire_les_infos() -> void:
	var v := _vue
	var au_sommet: bool = v.level >= v.maxLevel
	_pastille.nombre = int(v.points)
	_points.text = "%s à dépenser" % Accords.nom(v.points, "point", "points") if v.points > 0.0 else "Aucun point à dépenser"
	_points.theme_type_variation = &"Points" if v.points > 0.0 else &"TexteDoux"
	_niveau.text = "Niveau %s / %s" % [D6Js.num_str(v.level), D6Js.num_str(v.maxLevel)]
	_experience.poser(1.0 if au_sommet else v.xp / v.xpNext)
	_experience_texte.text = "Niveau maximum" if au_sommet else "%s / %s d'expérience" % [D6Js.num_str(v.xp), D6Js.num_str(v.xpNext)]

## L'arc (les boutons du jeu) : ce que porte chaque emplacement, lequel est choisi ; et la note
## d'en-tête, qui les nomme en toutes lettres.
func _montrer_les_emplacements() -> void:
	var portes: Array = app.profil.loadout.slots
	var pictos: Array = []
	var noms: Array = []
	for i in portes.size():
		pictos.append(String(_action(portes[i]).get("icon", "")))
		noms.append("%d · %s" % [i + 1, _action(portes[i]).get("name", VIDE)])
	_note.text = NOTE % [app.contenu.classes[app.profil.loadout.classId].name, ", ".join(noms)]
	_arc.montrer(pictos, _emplacement)

func _montrer_le_panneau(classe: String) -> void:
	var portes: Array = app.profil.loadout.slots
	if _devant == "emplacement" and _emplacement >= 0:
		_panneau.montrer_emplacement({"index": _emplacement, "action": _action(portes[_emplacement]), "refus": _refus})
		return
	var n := _noeud(_selection)
	if n.is_empty():
		return
	var x := _action_de(n)
	var place: int = portes.find(x.get("id")) if not x.is_empty() else -1
	var d := {
		"n": n, "sorte": _sorte(n, x, classe), "place": place, "placable": x.get("unlocked", false),
		"badge": "● Emplacement %d" % (place + 1) if place >= 0 else ("Offert" if n.free and n.rank == 1.0 else ""),
		"a_confirmer": _a_confirmer.trim_prefix("%s:" % n.id) if _a_confirmer.begins_with("%s:" % n.id) else "",
		"refus": _refus,
	}
	d.merge(_rappel(n, x, classe))
	_panneau.montrer_noeud(d)

## La sorte du nœud : « Compétence », « Compétence à charges », « Passif » (son étage se lit sur
## l'arbre) ; « Déplacement · Revenant », « Ultime · Revenant » (ils sont ceux de la classe).
func _sorte(n: Dictionary, x: Dictionary, classe: String) -> String:
	if n.kind == "move" or n.kind == "ultimate":
		return "%s · %s" % [SORTES[n.kind], app.contenu.classes[classe].name]
	return A_CHARGES if x.get("kind") == "gadget" else String(SORTES.get(n.kind, ""))

## Ce que la chose EST, à côté de ce que donne son rang : le texte de la compétence ; pour le
## déplacement et l'ultime, le nom et le texte de celui de la classe (données : moves, supers).
func _rappel(n: Dictionary, x: Dictionary, classe: String) -> Dictionary:
	var c: Dictionary = app.contenu.classes[classe]
	var base = null
	if n.kind == "move":
		base = app.contenu.moves.get(c.get("move"))
	elif n.kind == "ultimate":
		base = app.contenu.supers.get(c.get("super"))
	if base is Dictionary:
		return {"rappel_nom": String(base.name), "rappel": String(base.get("text", ""))}
	return {"rappel": String(x.get("text", "")) if n.rank > 0.0 else ""}

func _ecrire_rendre() -> void:
	var pris := false
	for etage in _vue.tiers:
		for n in etage.nodes:
			pris = pris or n.choices.any(func(ch: Dictionary) -> bool: return ch.taken)
	var texte := "Confirmer : tout rendre (%s or)" if _rendre_confirme else "Tout rendre (%s or)"
	_rendre.text = texte % D6Js.num_str(_vue.respecCost)
	_rendre.theme_type_variation = &"BoutonDanger" if _rendre_confirme else &"BoutonDiscret"
	_rendre.disabled = _vue.spent <= 0.0 and not pris
	var refus := _raison(CLE_RENDRE)
	_refus_rendre.text = refus if refus != "" else (AVIS_RENDRE if _rendre_confirme else "")
	_refus_rendre.theme_type_variation = &"Refus" if refus != "" else &"TexteDoux"

# ---------------------------------------------------------------- ce que le joueur touche

func _redessiner() -> void:
	dessin_demande.emit()

## Un nœud est choisi (touché, ou atteint par le focus) : le panneau le montre. Une confirmation
## en attente est oubliée ; un emplacement choisi sur l'arc reste en attente d'une compétence.
func _sur_noeud_choisi(id: String) -> void:
	_selection = id
	_devant = "noeud"
	_a_confirmer = ""
	_rendre_confirme = false
	_redessiner()

## Un nœud est APPUYÉ. Un emplacement attendait : la compétence acquise y va (sinon l'attente est
## oubliée). Rien n'attendait : au clavier ou à la manette, le focus passe au bouton du panneau.
func _sur_noeud_valide(id: String) -> void:
	var x := _action_de(_noeud(id))
	if _emplacement >= 0:
		var index := _emplacement
		_emplacement = -1
		if x.get("unlocked", false):
			operation_demandee.emit("placer:%s:%d" % [id, index], "select_slot", [float(index), x.id])
		else:
			_redessiner()
	elif _au_clavier and not _panneau.bouton_acheter().disabled:
		_panneau.bouton_acheter().grab_focus()

## Un emplacement est touché sur l'arc : le panneau le montre (« Vider »), et il attend une
## compétence ; le toucher de nouveau l'oublie.
func _sur_emplacement(index: int) -> void:
	_emplacement = -1 if _emplacement == index else index
	_devant = "emplacement" if _emplacement >= 0 else "noeud"
	_a_confirmer = ""
	_rendre_confirme = false
	_redessiner()

func _sur_achat() -> void:
	_a_confirmer = ""
	_rendre_confirme = false
	operation_demandee.emit("arbre:%s" % _selection, "tree_buy", [String(app.profil.loadout.classId), _selection])

## Une amélioration exclusive : le premier appui demande confirmation (le choix est définitif), le
## second la prend.
func _sur_choix(id: String) -> void:
	var cle := "%s:%s" % [_selection, id]
	_rendre_confirme = false
	if _a_confirmer != cle:
		_a_confirmer = cle
		_redessiner()
		return
	_a_confirmer = ""
	operation_demandee.emit("arbre:%s" % cle, "tree_choose", [String(app.profil.loadout.classId), _selection, id])

func _sur_placement(index: int) -> void:
	var x := _action_de(_noeud(_selection))
	_emplacement = -1
	_a_confirmer = ""
	operation_demandee.emit("placer:%s:%d" % [_selection, index], "select_slot", [float(index), x.get("id")])

func _sur_vidage() -> void:
	if _emplacement >= 0:
		operation_demandee.emit("slots:%d" % _emplacement, "select_slot", [float(_emplacement), null])

## « Tout rendre » : un premier appui demande confirmation (c'est payant), le second rend les points.
func _sur_rendre() -> void:
	_a_confirmer = ""
	if not _rendre_confirme:
		_rendre_confirme = true
		_redessiner()
		return
	_rendre_confirme = false
	operation_demandee.emit(CLE_RENDRE, "tree_respec", [String(app.profil.loadout.classId)])

## L'onglet quitté puis rouvert ne garde ni choix à moitié fait, ni confirmation en attente.
func _oublier() -> void:
	if not is_visible_in_tree():
		_selection = ""
		_emplacement = -1
		_devant = "noeud"
		_rendre_confirme = false
		_a_confirmer = ""

# ---------------------------------------------------------------- clavier, manette, écran

## Qui tient la main : le clavier ou la manette (le focus suit), ou bien le doigt ou la souris.
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey or ev is InputEventJoypadButton or ev is InputEventAction:
		_au_clavier = true
	elif ev is InputEventMouseButton or ev is InputEventScreenTouch:
		_au_clavier = false

## Retour (Échap, B) depuis le panneau : le focus revient au nœud choisi, sans quitter la Ville.
func _unhandled_input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or not ev.is_action_pressed("ui_cancel"):
		return
	var tenu := get_viewport().gui_get_focus_owner()
	var noeud_n: Button = _arbre.bouton(_selection)
	if tenu != null and noeud_n != null and _panneau.is_ancestor_of(tenu):
		noeud_n.grab_focus()
		get_viewport().set_input_as_handled()

## La place que la Ville offre à l'onglet (elle le dit quand sa fenêtre change) : c'est elle, et
## non la taille de l'onglet (qui grandit avec ce qu'il montre), qui décide de ce qui tient.
func tenir_dans(place: Vector2) -> void:
	_place = place
	if is_node_ready():
		_adapter()

## Le panneau de détail prend la largeur dont l'arbre n'a pas besoin (peu de nœuds par étage : un
## texte plus large, donc moins haut) ; un arbre chargé le ramène à sa largeur minimale.
func _partager_la_largeur() -> void:
	var reste: float = size.x - _infos.size.x - _arbre.largeur_aisee(_vue, PAS_AISE) - 2.0 * _corps.get_theme_constant("separation")
	var voulu := PANNEAU.x if _corps.vertical else clampf(reste, PANNEAU.x, PANNEAU.y)
	if not is_equal_approx(_cadre.custom_minimum_size.x, voulu):
		_cadre.custom_minimum_size.x = voulu

## Paysage : trois colonnes, l'arbre seul défile. Portrait : tout s'empile, la page de la Ville défile.
func _adapter() -> void:
	var etroit := size.x < LARGEUR_ETROITE
	_note.visible = etroit or _place.y >= HAUTEUR_AISEE # l'arc montre la même chose, en dessin
	if not _vue.is_empty():
		_partager_la_largeur()
	if _corps.vertical == etroit:
		return
	_corps.vertical = etroit
	var mode := ScrollContainer.SCROLL_MODE_DISABLED if etroit else ScrollContainer.SCROLL_MODE_AUTO
	_defile.vertical_scroll_mode = mode
	_panneau_defile.vertical_scroll_mode = mode
