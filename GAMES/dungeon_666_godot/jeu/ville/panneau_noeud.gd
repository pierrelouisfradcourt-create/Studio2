extends VBoxContainer
## Le PANNEAU DE DÉTAIL du Grimoire : ce que dit le nœud choisi dans l'arbre — son nom, sa sorte,
## son rang, le texte du rang ACTUEL et celui du rang SUIVANT (les mots qui changent en évidence),
## le bouton « Apprendre » / « Améliorer » (grisé avec la raison des règles), ses deux améliorations
## exclusives (« Choisir », puis « Confirmer » : le choix est définitif) et, pour une compétence
## acquise, « Placer en 1 / 2 / 3 ». Quand c'est un EMPLACEMENT qui est choisi (touché sur l'arc),
## il dit ce qu'il porte et offre « Vider ».
##
## Aucune règle ici, et aucune lecture du profil : l'onglet (jeu/ville/onglet_grimoire.gd) lui
## DÉCRIT ce qu'il montre, lui signale ce que le joueur demande. Les textes chiffrés, les raisons
## d'un bouton grisé viennent tels quels de D6Profile.tree_view.

signal achat_demande
signal choix_demande(id: String)
signal placement_demande(index: int)
signal vidage_demande

const Style = preload("res://jeu/theme/theme.gd")

const SUIVANT := "→ %s"
const PAS_APPRIS := "Pas encore appris."
const AVIS := "Ce choix est définitif, sauf à tout rendre."
const TITRE_CHOIX := "Améliorations · %s"
const L_UNE_OU_L_AUTRE := "une seule"
const AIDE_EMPLACEMENT := "Appuie sur une compétence acquise de l'arbre pour la placer ici."
const LARGEUR_BOUTON := 86.0

@onready var _sorte: Label = %Sorte
@onready var _badge: Label = %Badge
@onready var _nom: Label = %Nom
@onready var _rang: Label = %Rang
@onready var _rappel_nom: Label = %RappelNom
@onready var _rappel: Label = %Rappel
@onready var _actuel: Label = %Actuel
@onready var _suivant: RichTextLabel = %Suivant
@onready var _acheter: Button = %Acheter
@onready var _raison: Label = %Raison
@onready var _refus: Label = %Refus
@onready var _titre_choix: Label = %TitreChoix
@onready var _choix: VBoxContainer = %Choix
@onready var _placer: HBoxContainer = %Placer
@onready var _places: Array = [%Placer1, %Placer2, %Placer3]
@onready var _vider: Button = %Vider

func _ready() -> void:
	_acheter.set_meta("action", "plus")
	_acheter.pressed.connect(func() -> void: achat_demande.emit())
	_vider.set_meta("action", "vider")
	_vider.pressed.connect(func() -> void: vidage_demande.emit())
	for i in _places.size():
		_places[i].set_meta("action", "placer")
		_places[i].pressed.connect(func() -> void: placement_demande.emit(i))

## Le bouton principal (« Apprendre » / « Améliorer »), pour le focus et les essais.
func bouton_acheter() -> Button:
	return _acheter

## Le texte du rang suivant, sans ses balises (pour les essais).
func suivant() -> String:
	return _suivant.get_parsed_text() if _suivant.visible else ""

# ---------------------------------------------------------------- un nœud

## `d` : {n : le nœud tel que le rend tree_view ; sorte : « Compétence », « Déplacement · Revenant » ;
## badge : « ● Emplacement 2 », « Offert » ;
## rappel_nom, rappel : ce que la chose EST (texte de la compétence, du déplacement, de l'ultime) ;
## place : l'emplacement qu'elle occupe (-1 : aucun) ; placable : elle peut être placée ;
## a_confirmer : l'amélioration qui attend son second appui ("" : aucune) ;
## refus : {clé de bouton: raison} du dernier refus des règles}
func montrer_noeud(d: Dictionary) -> void:
	var n: Dictionary = d.n
	var cle := "arbre:%s" % n.id
	_ecrire_tete(d.sorte, d.get("badge", ""), n.name, "Rang %s / %s" % [D6Js.num_str(n.rank), D6Js.num_str(n.maxRank)])
	_texte(_rappel_nom, d.get("rappel_nom", ""))
	_texte(_rappel, d.get("rappel", ""))
	_texte(_actuel, n.now if n.now != "" else PAS_APPRIS)
	_suivant.visible = n.next != ""
	_suivant.text = SUIVANT % _en_evidence(n.now, n.next)
	_acheter.visible = true
	_acheter.text = "Améliorer" if n.rank > 0.0 else "Apprendre"
	_acheter.disabled = not n.canBuy
	_acheter.theme_type_variation = &"BoutonPrincipal" if n.canBuy else &""
	_acheter.set_meta("cle", cle)
	_texte(_raison, "" if n.canBuy else _dire(n.reason))
	_texte(_refus, _dire(String(d.get("refus", {}).get(cle, ""))))
	_ecrire_les_choix(n, cle, d.get("a_confirmer", ""), d.get("refus", {}))
	_ecrire_les_places(String(n.id), d.get("placable", false), d.get("place", -1), d.get("refus", {}))
	_vider.visible = false

## `d` : {index : l'emplacement (0, 1, 2) ; action : {name, text} de ce qu'il porte ({} : vide) ; refus}
func montrer_emplacement(d: Dictionary) -> void:
	var action: Dictionary = d.get("action", {})
	var cle := "slots:%d" % d.index
	_ecrire_tete("Emplacement %d" % (d.index + 1), "", action.get("name", "Vide"), "")
	_texte(_rappel_nom, "")
	_texte(_rappel, action.get("text", ""))
	_texte(_actuel, AIDE_EMPLACEMENT)
	_suivant.visible = false
	_acheter.visible = false
	_texte(_raison, "")
	_texte(_refus, _dire(String(d.get("refus", {}).get(cle, ""))))
	_ecrire_les_choix({"choices": []}, cle, "", {})
	_placer.visible = false
	_vider.visible = true
	_vider.disabled = action.is_empty()
	_vider.set_meta("cle", cle)

# ---------------------------------------------------------------- pièces

func _ecrire_tete(sorte: String, badge: String, nom: String, rang: String) -> void:
	_sorte.text = sorte
	_texte(_badge, badge)
	_nom.text = nom
	_texte(_rang, rang)

func _texte(label: Label, texte: String) -> void:
	label.text = texte
	label.visible = texte != ""

## Une raison telle qu'on l'affiche : première lettre en capitale.
func _dire(raison: String) -> String:
	return raison.left(1).to_upper() + raison.substr(1)

## Le texte du rang suivant, les MOTS qui diffèrent du rang actuel mis en évidence (un nombre qui
## change, un mot nouveau). Simple comparaison de deux textes rendus par les règles : rien n'est calculé.
func _en_evidence(actuel: String, suivant: String) -> String:
	var avant := actuel.split(" ")
	var apres := suivant.split(" ")
	var meme_forme := avant.size() == apres.size()
	var mots: Array = []
	for i in apres.size():
		var neuf: bool = meme_forme and apres[i] != avant[i]
		mots.append(Style.evidence(apres[i]) if neuf else apres[i])
	return " ".join(mots)

## Les améliorations exclusives : prise (●, sans bouton), écartée (✕, l'autre est prise : plus de bouton), offerte
## (« Choisir », puis « Confirmer »), pas encore offerte (sans bouton ; la raison des règles est au titre).
func _ecrire_les_choix(n: Dictionary, cle: String, a_confirmer: String, refus: Dictionary) -> void:
	for ancien in _choix.get_children():
		_choix.remove_child(ancien)
		ancien.queue_free()
	var choix: Array = n.choices
	var une_prise: bool = choix.any(func(ch: Dictionary) -> bool: return ch.taken)
	for ch: Dictionary in choix:
		_choix.add_child(_ligne_de_choix(ch, "%s:%s" % [cle, ch.id], une_prise, a_confirmer == ch.id, refus))
	_titre_choix.visible = not choix.is_empty()
	# Pas encore offertes : le titre dit pourquoi (la raison des règles, la même pour les deux).
	var offertes: bool = une_prise or choix.any(func(ch: Dictionary) -> bool: return ch.canTake)
	_titre_choix.text = TITRE_CHOIX % (L_UNE_OU_L_AUTRE if offertes or choix.is_empty() else String(choix[0].reason))
	# Une confirmation attend : l'avis prend la place du titre, juste au-dessus des deux boutons.
	if a_confirmer != "":
		_titre_choix.text = AVIS
	_titre_choix.theme_type_variation = &"Refus" if a_confirmer != "" else &"SurTitreDoux"
	_titre_choix.uppercase = a_confirmer == ""
	_choix.visible = not choix.is_empty()

func _ligne_de_choix(ch: Dictionary, cle: String, une_prise: bool, confirme: bool, refus: Dictionary) -> Control:
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 6)
	var textes := VBoxContainer.new()
	textes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textes.add_theme_constant_override("separation", 0)
	ligne.add_child(textes)
	var ecartee: bool = une_prise and not ch.taken
	textes.add_child(_etiquette("%s %s" % ["●" if ch.taken else ("✕" if ecartee else "◇"), ch.name], &"Valeur" if ch.taken else (&"TexteDoux" if ecartee else &"Texte")))
	textes.add_child(_etiquette(ch.text, &"Petit"))
	var raison := _dire(String(refus.get(cle, "")))
	if raison != "":
		textes.add_child(_etiquette(raison, &"Refus"))
	if ch.canTake:
		ligne.add_child(_bouton_de_choix(ch, cle, confirme))
	return ligne

func _bouton_de_choix(ch: Dictionary, cle: String, confirme: bool) -> Button:
	var b := Button.new()
	b.text = "Confirmer" if confirme else "Choisir"
	b.theme_type_variation = &"BoutonDanger" if confirme else &"BoutonPetitPrincipal"
	b.custom_minimum_size = Vector2(LARGEUR_BOUTON, Style.CIBLE)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.set_meta("cle", cle)
	b.set_meta("action", "choix:%s" % ch.id)
	b.pressed.connect(func() -> void: choix_demande.emit(String(ch.id)))
	return b

func _etiquette(texte: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = texte
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## « Placer en 1 / 2 / 3 » : l'emplacement qu'elle occupe déjà est doré (et ne se rappuie pas).
func _ecrire_les_places(id: String, placable: bool, place: int, refus: Dictionary) -> void:
	_placer.visible = placable
	for i in _places.size():
		var b: Button = _places[i]
		var cle := "placer:%s:%d" % [id, i]
		b.set_meta("cle", cle)
		b.disabled = i == place
		b.tooltip_text = "Déjà dans l'emplacement %d" % (i + 1) if i == place else "Placer dans l'emplacement %d" % (i + 1)
		if refus.has(cle):
			_texte(_refus, _dire(String(refus[cle])))
