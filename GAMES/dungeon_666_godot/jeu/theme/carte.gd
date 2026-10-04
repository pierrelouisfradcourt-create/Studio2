extends PanelContainer
## LA carte du jeu, commune aux écrans (bénédiction, butin, marchand, mort…) et à la Ville :
## bandeau d'accent, sur-titre et badge, titre, sous-titre, lignes de texte, refus, et un pied
## (prix + boutons). Elle n'a aucune règle : on lui DÉCRIT ce qu'elle montre, elle signale le
## bouton pressé (`action`) ou, si toute la carte est à choisir, qu'on l'a choisie (`choisie`).
##
##   carte.decrire({
##     "surtitre": "Super : Colère", "surtitre_doux": false, "titre": "Revenant", "sous": "…",
##     "lignes": ["texte", {"texte": "+12 % dégâts", "genre": "Affixe"}],   # genre = variation de Label
##     "etat": "" | "equipe" | "verrouille" | "vide",   "badge": "Équipé",   "cher": true,
##     "accent": Color, "couleur_titre": Color,          # sinon : selon l'état
##     "prix": "◆ 120", "refus": "Âmes insuffisantes",
##     "boutons": [{"nom": "debloquer", "texte": "Débloquer", "genre": "principal" | "danger" | "discret" | "petit" | "", "inactif": false, "cle": "classes:bourreau"}],
##     "a_choisir": true,   # toute la carte est un bouton (survol, appui, focus)
##     "grisee": true,      # lisible, mais on ne peut pas la prendre
##     "picto": Control,    # un dessin déjà fait (pictogramme d'une action), posé en tête, à gauche
##   })
## Toute clé est facultative ; un champ vide ne prend pas de place.

signal action(nom: String)
signal choisie

const ThemeJeu = preload("res://jeu/theme/theme.gd")
const PANNEAUX := {"": &"Carte", "equipe": &"CarteEquipee", "verrouille": &"CarteVerrouillee", "vide": &"CarteVide"}
const BADGES := {"": "", "equipe": "● Équipé", "verrouille": "Verrouillé", "vide": ""}
const BOUTONS := {"": &"", "principal": &"BoutonPrincipal", "danger": &"BoutonDanger", "discret": &"BoutonDiscret", "petit": &"BoutonPetit"}
const OPACITE_TITRE_VIDE := 0.55

@onready var _fond: Button = %Fond
@onready var _colonne: VBoxContainer = %Colonne
@onready var _bandeau: Panel = %Bandeau
@onready var _tete: HBoxContainer = %Tete
@onready var _surtitre: Label = %SurTitre
@onready var _badge: Label = %Badge
@onready var _titre: Label = %Titre
@onready var _sous: Label = %Sous
@onready var _lignes: VBoxContainer = %Lignes
@onready var _refus: Label = %Refus
@onready var _pied: HBoxContainer = %Pied
@onready var _prix: Label = %Prix
@onready var _boutons: HFlowContainer = %Boutons

var _picto: Control = null

func _ready() -> void:
	_fond.pressed.connect(func() -> void: choisie.emit())

func decrire(d: Dictionary) -> void:
	var etat: String = d.get("etat", "")
	var accent: Color = d.get("accent", ThemeJeu.accent(etat))
	_bandeau.self_modulate = accent
	_poser_picto(d.get("picto"))
	_ecrire_tete(d, etat, accent)
	_texte(_titre, d.get("titre", ""))
	_titre.self_modulate = d.get("couleur_titre", Color.WHITE)
	_titre.modulate.a = OPACITE_TITRE_VIDE if etat == "vide" else 1.0
	_texte(_sous, d.get("sous", ""))
	_ecrire_lignes(d.get("lignes", []))
	_texte(_refus, d.get("refus", ""))
	_texte(_prix, d.get("prix", ""))
	_prix.theme_type_variation = &"PrixCher" if d.get("cher", false) else &"Prix"
	_poser_boutons(d.get("boutons", []))
	_pied.visible = _prix.visible or _boutons.get_child_count() > 0
	# Carte à choisir : le bouton fait le fond (et le panneau s'efface).
	_fond.visible = d.get("a_choisir", false)
	theme_type_variation = &"PanneauNu" if _fond.visible else PANNEAUX.get(etat, PANNEAUX[""])
	griser(d.get("grisee", false))

## Carte grisée : lisible, mais on ne peut pas la choisir.
func griser(grisee: bool) -> void:
	_fond.disabled = grisee
	_fond.focus_mode = Control.FOCUS_NONE if grisee else Control.FOCUS_ALL
	_colonne.modulate.a = ThemeJeu.OPACITE_GRISE if grisee else 1.0

## Le bouton d'action `nom` (null s'il n'existe pas) ; sans nom, le fond d'une carte à choisir.
func bouton(nom: String = "") -> Button:
	for b in _boutons.get_children():
		if b.get_meta("action", "") == nom:
			return b
	return _fond if nom == "" and _fond.visible else null

func _ecrire_tete(d: Dictionary, etat: String, accent: Color) -> void:
	_texte(_surtitre, d.get("surtitre", ""))
	var doux: bool = d.get("surtitre_doux", false)
	_surtitre.theme_type_variation = &"SurTitreDoux" if doux else &"SurTitre"
	# Le sur-titre prend la couleur d'accent quand la carte en donne une (famille, rareté).
	_surtitre.remove_theme_color_override("font_color")
	if d.has("accent") and not doux:
		_surtitre.add_theme_color_override("font_color", accent)
	_texte(_badge, d.get("badge", BADGES.get(etat, "")))
	_badge.theme_type_variation = &"Badge" if etat == "equipe" else &"BadgeDoux"
	_tete.visible = _surtitre.visible or _badge.visible or _picto != null

## Le dessin de tête (la carte en devient propriétaire) ; l'ancien, s'il y en a un, s'en va.
func _poser_picto(picto) -> void:
	if _picto != null:
		_tete.remove_child(_picto)
		_picto.queue_free()
		_picto = null
	if picto is Control:
		_picto = picto
		_tete.add_child(picto)
		_tete.move_child(picto, 0)

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
		bouton_n.custom_minimum_size = Vector2(0.0, ThemeJeu.CIBLE)
		bouton_n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bouton_n.mouse_filter = Control.MOUSE_FILTER_PASS # la molette et le doigt qui glisse défilent aussi par-dessus
		bouton_n.set_meta("action", b.get("nom", ""))
		bouton_n.set_meta("cle", b.get("cle", ""))
		bouton_n.pressed.connect(_sur_bouton.bind(b.get("nom", "")))
		_boutons.add_child(bouton_n)

func _sur_bouton(nom: String) -> void:
	action.emit(nom)
