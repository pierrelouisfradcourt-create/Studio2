extends VBoxContainer
## Base d'un onglet de la Ville. Un onglet LIT `app.profil` et `app.contenu`, pose des cartes, et
## DEMANDE ses opérations par signal : c'est la Ville (ville.gd) qui appelle
## `app.operation_ville`, retient un éventuel refus et redessine. Aucun onglet n'écrit le profil.

## Opération de la Ville demandée par un bouton ; `cle` désigne la carte (pour y afficher le refus
## et y rendre le focus après le redessin).
signal operation_demandee(cle: String, nom: String, args: Array)
## L'onglet veut être redessiné sans opération (ex. : un recyclage attend sa confirmation).
signal dessin_demande

const Carte = preload("res://jeu/theme/carte.tscn")
const Style = preload("res://jeu/theme/theme.gd")
const TROP_CHER := "Âmes insuffisantes"

var app: Node
var partie: Node
var _refus: Dictionary = {} # clé de carte -> raison du dernier refus

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie

## Redessine l'onglet d'après le profil. `refus` : le refus à afficher (clé de carte -> raison).
func dessiner(refus: Dictionary = {}) -> void:
	if app == null or not is_node_ready():
		return
	_refus = refus
	_dessiner()

func _dessiner() -> void:
	pass

## La place que la Ville offre à l'onglet (la taille de sa zone de défilement), dite à chaque
## changement de fenêtre : un onglet qui veut tenir sans défiler s'y mesure.
func tenir_dans(_place: Vector2) -> void:
	pass

## Où rendre le focus (clavier, manette) quand le bouton qui le tenait a disparu au redessin ;
## null : à l'onglet lui-même.
func repli_du_focus() -> Control:
	return null

# ---------------------------------------------------------------- briques communes

func _vider(conteneur: Node) -> void:
	for enfant in conteneur.get_children():
		conteneur.remove_child(enfant)
		enfant.queue_free()

func _carte(conteneur: Node, d: Dictionary) -> Node:
	var carte := Carte.instantiate()
	conteneur.add_child(carte)
	carte.decrire(d)
	return carte

func _ames(nombre) -> String:
	return "◆ %s" % D6Js.num_str(nombre)

## Raison d'un refus, telle qu'on l'affiche (« Âmes insuffisantes »).
func _raison(cle: String) -> String:
	var r := String(_refus.get(cle, ""))
	return r.left(1).to_upper() + r.substr(1)

func _nom(table: Dictionary, id) -> String:
	var entree = table.get(id)
	return String(entree.name) if entree is Dictionary else "?"

## Type d'arme d'un objet (un objet ancien sans type est une Lame, comme dans D6Profile).
func _type_arme(objet) -> String:
	if not (objet is Dictionary):
		return D6Profile.DEFAULT_WEAPON
	return D6Js.nz(objet.get("weaponType"), D6Profile.DEFAULT_WEAPON)

## Pied d'une entrée de contenu (classe, compétence, gadget) : équipée / à choisir / à débloquer
## avec son prix, grisée si les Âmes manquent. Complète la description `d` de la carte.
func _pied_contenu(d: Dictionary, genre: String, id: String, equipe: bool) -> void:
	var cle := "%s:%s" % [genre, id]
	d.refus = _raison(cle)
	if equipe:
		d.etat = "equipe"
		d.boutons = [{"nom": "", "texte": "Équipé", "inactif": true, "cle": cle}]
	elif app.profil.unlocked[genre].has(id):
		d.boutons = [{"nom": "choisir", "texte": "Choisir", "genre": "principal", "cle": cle}]
	else:
		_pied_achat(d, cle, "debloquer", "Débloquer", D6Profile.unlock_cost(app.contenu, genre, id))
		d.etat = "verrouille"

## Pied d'un achat en Âmes : le prix, et un bouton grisé (avec la raison) si les Âmes manquent.
func _pied_achat(d: Dictionary, cle: String, nom: String, texte: String, prix: float) -> void:
	var cher: bool = app.profil.souls < prix
	d.prix = _ames(prix)
	d.cher = cher
	if cher and d.get("refus", "") == "":
		d.refus = TROP_CHER
	d.boutons = [{"nom": nom, "texte": texte, "genre": "" if cher else "principal", "inactif": cher, "cle": cle}]

## Bouton d'une carte de contenu : choisir (opération `op_choisir`) ou débloquer.
func _sur_contenu(nom: String, genre: String, id: String, op_choisir: String) -> void:
	var cle := "%s:%s" % [genre, id]
	if nom == "choisir":
		operation_demandee.emit(cle, op_choisir, [id])
	elif nom == "debloquer":
		operation_demandee.emit(cle, "unlock", [genre, id])

## Description de carte d'un objet d'équipement (texte : D6Run.describe_item) ; null = emplacement vide.
func _fiche_objet(objet, surtitre: String) -> Dictionary:
	var o = D6Run.describe_item(objet)
	if o == null:
		return {"surtitre": surtitre, "titre": "Emplacement vide", "etat": "vide"}
	var lignes: Array = []
	for ligne in o.lines:
		lignes.append({"texte": ligne, "genre": "Affixe"})
	if o.power != null:
		lignes.append({"texte": "★ %s" % o.power, "genre": "Pouvoir"})
	var couleur := Color(String(o.color))
	return {
		"surtitre": surtitre, "titre": o.name, "couleur_titre": couleur, "accent": couleur,
		"sous": "%s · %s · niv. %s" % [o.rarityName, o.slotName, D6Js.num_str(o.level)], "lignes": lignes,
	}
