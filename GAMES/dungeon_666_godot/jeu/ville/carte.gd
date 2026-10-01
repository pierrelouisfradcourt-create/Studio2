extends PanelContainer
## La carte de la Ville : bandeau d'accent, sur-titre, titre, sous-titre, lignes de texte, et un
## pied (prix + boutons). Réutilisée par tous les onglets. Elle n'a aucune règle : on lui DÉCRIT
## ce qu'elle montre, elle signale le bouton pressé.
##
##   carte.decrire({
##     "surtitre": "Super : Colère", "titre": "Revenant", "sous": "…",
##     "lignes": ["texte", {"texte": "+12 % dégâts", "genre": "Affixe"}],   # genre = variation de Label
##     "etat": "" | "equipe" | "verrouille" | "vide",   "badge": "Équipé",   "cher": true,
##     "accent": Color, "couleur_titre": Color,          # sinon : selon l'état
##     "prix": "◆ 120", "refus": "Âmes insuffisantes",
##     "boutons": [{"nom": "debloquer", "texte": "Débloquer", "genre": "primaire" | "danger" | "", "inactif": false, "cle": "classes:bourreau"}],
##   })

signal action(nom: String)

const Style = preload("res://jeu/ville/style_ville.gd")
const PANNEAUX := {"": &"Carte", "equipe": &"CarteEquipee", "verrouille": &"CarteVerrouillee", "vide": &"CarteVide"}
const BADGES := {"": "", "equipe": "● Équipé", "verrouille": "Verrouillé", "vide": ""}
const BOUTONS := {"": &"", "primaire": &"BoutonPrimaire", "danger": &"BoutonDanger", "discret": &"BoutonDiscret"}

@onready var _bandeau: Panel = $Colonne/Bandeau
@onready var _surtitre: Label = $Colonne/Marge/Contenu/Tete/Surtitre
@onready var _badge: Label = $Colonne/Marge/Contenu/Tete/Badge
@onready var _titre: Label = $Colonne/Marge/Contenu/Titre
@onready var _sous: Label = $Colonne/Marge/Contenu/Sous
@onready var _lignes: VBoxContainer = $Colonne/Marge/Contenu/Lignes
@onready var _refus: Label = $Colonne/Marge/Contenu/Refus
@onready var _pied: HBoxContainer = $Colonne/Marge/Contenu/Pied
@onready var _prix: Label = $Colonne/Marge/Contenu/Pied/Prix
@onready var _boutons: HFlowContainer = $Colonne/Marge/Contenu/Pied/Boutons

func decrire(d: Dictionary) -> void:
	var etat: String = d.get("etat", "")
	theme_type_variation = PANNEAUX.get(etat, PANNEAUX[""])
	_bandeau.self_modulate = d.get("accent", Style.accent(etat))
	_texte(_surtitre, d.get("surtitre", ""))
	_texte(_badge, d.get("badge", BADGES.get(etat, "")))
	_badge.theme_type_variation = &"Badge" if etat == "equipe" else &"BadgeDoux"
	_texte(_titre, d.get("titre", ""))
	_titre.self_modulate = d.get("couleur_titre", Color.WHITE)
	_titre.modulate.a = 0.55 if etat == "vide" else 1.0
	_texte(_sous, d.get("sous", ""))
	_ecrire_lignes(d.get("lignes", []))
	_texte(_refus, d.get("refus", ""))
	_texte(_prix, d.get("prix", ""))
	_prix.theme_type_variation = &"PrixCher" if d.get("cher", false) else &"Prix"
	_poser_boutons(d.get("boutons", []))
	_pied.visible = _prix.visible or _boutons.get_child_count() > 0

## Le bouton d'action `nom` (null s'il n'existe pas) : pour le focus et pour les essais.
func bouton(nom: String) -> Button:
	for b in _boutons.get_children():
		if b.get_meta("action", "") == nom:
			return b
	return null

func _texte(label: Label, texte: String) -> void:
	label.text = texte
	label.visible = texte != ""

func _ecrire_lignes(lignes: Array) -> void:
	for ancien in _lignes.get_children():
		_lignes.remove_child(ancien)
		ancien.queue_free()
	for ligne in lignes:
		var l := Label.new()
		l.text = ligne.texte if ligne is Dictionary else String(ligne)
		l.theme_type_variation = StringName(ligne.get("genre", "Texte")) if ligne is Dictionary else &"Texte"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lignes.add_child(l)
	_lignes.visible = not lignes.is_empty()

func _poser_boutons(boutons: Array) -> void:
	for ancien in _boutons.get_children():
		_boutons.remove_child(ancien)
		ancien.queue_free()
	for b in boutons:
		var bouton_n := Button.new()
		bouton_n.text = b.get("texte", "")
		bouton_n.disabled = b.get("inactif", false)
		bouton_n.theme_type_variation = BOUTONS.get(b.get("genre", ""), &"")
		bouton_n.custom_minimum_size = Vector2(0.0, Style.CIBLE)
		bouton_n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bouton_n.mouse_filter = Control.MOUSE_FILTER_PASS # la molette et le doigt qui glisse défilent aussi par-dessus
		bouton_n.set_meta("action", b.get("nom", ""))
		bouton_n.set_meta("cle", b.get("cle", ""))
		bouton_n.pressed.connect(_sur_bouton.bind(b.get("nom", "")))
		_boutons.add_child(bouton_n)

func _sur_bouton(nom: String) -> void:
	action.emit(nom)
