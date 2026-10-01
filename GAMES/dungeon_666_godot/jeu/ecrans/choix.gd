extends VBoxContainer
## Les menus de choix en partie, selon `game.choice.kind` : bénédiction, butin, marchand, autel,
## chambre forte, fontaine (buildBoon, buildLoot, buildShop, buildEvent, buildCalm du web).
## Tout ce qui s'affiche vient de `game.choice` (décrit par la simulation) ; chaque bouton émet
## la commande que la simulation attend, et ce qu'elle refuserait est grisé.

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const Carte = preload("res://jeu/ecrans/carte.tscn")
const Fabrique = preload("res://jeu/ecrans/fabrique.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")

const LARGEUR := 760.0
const CARTE_MIN := 190.0
const CARTE_OBJET_MIN := 220.0
## Libellés des emplacements d'une bénédiction (SLOT_LABELS de menus.mjs).
const EMPLACEMENTS := {"attack": "Attaque", "dash": "Dash", "skill": "Compétence", "passive": "Passif", "super": "Super"}
const SEP := " · "

@onready var _titre: Label = %Titre
@onready var _accroche: Label = %Accroche
@onready var _cartes: GridContainer = %Cartes
@onready var _options: VBoxContainer = %Options
@onready var _actions: HFlowContainer = %Actions

func ouvrir(_app: Node, partie: Node) -> void:
	var ch: Dictionary = partie.game.choice
	match ch.kind:
		"boon": _benediction(ch)
		"loot": _butin(ch)
		"shop": _marchand(ch)
		"event": _evenement(ch)
		_: _salle_calme(ch)

func largeur() -> float:
	return LARGEUR

func _choisir(index: int) -> void:
	commande.emit({"type": "choose", "index": float(index)})

func _en_tete(titre: String, accroche: String, couleur = null, variation: StringName = &"") -> void:
	_titre.text = titre
	if couleur != null:
		_titre.add_theme_color_override("font_color", Fabrique.couleur(couleur, _titre.get_theme_color("font_color")))
	_accroche.text = accroche
	if variation != &"":
		_accroche.theme_type_variation = variation

func _poser_carte(d: Dictionary) -> Control:
	var carte := Carte.instantiate()
	_cartes.add_child(carte)
	carte.remplir(d)
	return carte

func _action(texte: String, variation: StringName, cmd: Dictionary, grise: bool = false) -> void:
	var b := Fabrique.bouton(texte, variation, grise)
	b.pressed.connect(func() -> void: commande.emit(cmd))
	_actions.add_child(b)
	_actions.visible = true

# ---------------------------------------------------------------- bénédiction

func _benediction(ch: Dictionary) -> void:
	_en_tete("Bénédiction" + SEP + String(ch.familyName), "Choisissez un don du péché. Il disparaîtra à votre mort.", ch.color)
	_cartes.largeur_min = CARTE_MIN
	for i in ch.options.size():
		var o: Dictionary = ch.options[i]
		var niveau: float = D6Js.nz(o.get("level"), 1.0)
		var sur_titre: String = ("DUO" + SEP if o.duo else "") + String(EMPLACEMENTS.get(o.slot, o.slot)) + SEP + String(o.rarityName)
		if niveau > 1.0:
			sur_titre += SEP + "niv. " + D6Js.num_str(niveau)
		var carte := _poser_carte({
			"accent": Fabrique.couleur(o.color, Couleurs.UI.ember), "sur_titre": sur_titre,
			"titre": o.name, "texte": o.text, "a_choisir": true,
		})
		carte.choisie.connect(_choisir.bind(i))

# ---------------------------------------------------------------- butin

func _butin(ch: Dictionary) -> void:
	_en_tete("Trésor", "Équipement PERMANENT : l'objet remplacé, ou celui que vous gardez, part au coffre de la Ville.", null, &"Petit")
	_cartes.largeur_min = CARTE_OBJET_MIN
	_poser_carte(_carte_objet(ch.item, "Trouvé"))
	_poser_carte(_carte_objet(ch.get("equipped"), "Porté"))
	var maniable: bool = ch.get("wieldable") != false
	_action("Équiper" if maniable else "Arme d'une autre classe", &"BoutonPrincipal", {"type": "equip"}, not maniable)
	_action("Garder au coffre", &"", {"type": "stash"})
	_action("Vendre" + SEP + "+" + D6Js.num_str(ch.salvage) + " or", &"", {"type": "salvage"})

## La carte d'un objet décrit par la simulation (describe_item), ou d'un emplacement vide.
func _carte_objet(objet, sur_titre: String) -> Dictionary:
	if not (objet is Dictionary):
		return {"sur_titre": sur_titre, "sur_titre_neutre": true, "titre": "Emplacement vide", "grisee": true}
	var couleur := Fabrique.couleur(objet.get("color"), Couleurs.UI.ink)
	return {
		"accent": couleur, "sur_titre": sur_titre, "sur_titre_neutre": true,
		"titre": String(objet.name), "couleur_titre": couleur,
		"sous_titre": SEP.join([objet.rarityName, objet.slotName, "niv. " + D6Js.num_str(D6Js.nz(objet.get("level"), 1.0))]),
		"lignes": objet.lines, "pouvoir": D6Js.nz(objet.get("power"), ""),
	}

# ---------------------------------------------------------------- marchand

func _marchand(ch: Dictionary) -> void:
	_en_tete("Marchand des âmes", "Votre or : " + D6Js.num_str(ch.gold), null, &"Or")
	_cartes.largeur_min = CARTE_MIN
	for i in ch.offers.size():
		var o: Dictionary = ch.offers[i]
		var vendu: bool = D6Js.truthy(o.get("sold"))
		var carte := _poser_carte(_carte_offre(o))
		var acheter := Fabrique.bouton("Vendu" if vendu else "Acheter" + SEP + D6Js.num_str(o.price) + " or", &"BoutonPetit", vendu or ch.gold < o.price)
		acheter.pressed.connect(_choisir.bind(i))
		carte.ajouter_au_pied(acheter)
	_action("Partir", &"", {"type": "close"})

func _carte_offre(o: Dictionary) -> Dictionary:
	var objet = o.get("item")
	if not (objet is Dictionary):
		return {"accent": Fabrique.couleur(o.get("color"), Couleurs.UI.ember), "titre": String(o.label), "texte": String(o.get("text", ""))}
	var d := _carte_objet(objet, "")
	d.sous_titre = SEP.join([objet.rarityName, objet.slotName])
	var porte = o.get("equipped")
	if porte is Dictionary:
		d.texte = "Remplace : " + String(porte.name)
	return d

# ---------------------------------------------------------------- autel, salles calmes

func _evenement(ch: Dictionary) -> void:
	_en_tete(String(ch.title), String(ch.text))
	_cartes.visible = false
	_options.visible = true
	for i in ch.options.size():
		var o: Dictionary = ch.options[i]
		var b := Fabrique.bouton_long(String(o.label), &"BoutonPrincipal" if i == 0 else &"", D6Js.truthy(o.get("disabled")))
		b.pressed.connect(_choisir.bind(i))
		_options.add_child(b)

## Chambre forte, fontaine de repos : trois cartes, une seule à prendre.
func _salle_calme(ch: Dictionary) -> void:
	_en_tete(String(ch.title), String(ch.text), ch.get("color"))
	_cartes.largeur_min = CARTE_MIN
	for i in ch.options.size():
		var o: Dictionary = ch.options[i]
		var carte := _poser_carte({
			"accent": Fabrique.couleur(D6Js.nz(o.get("color"), ch.get("color")), Couleurs.UI.ember),
			"sur_titre": String(o.kicker), "titre": String(o.label), "texte": String(o.text),
			"a_choisir": true, "grisee": D6Js.truthy(o.get("disabled")),
		})
		carte.choisie.connect(_choisir.bind(i))
