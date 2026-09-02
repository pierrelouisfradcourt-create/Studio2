# content_provider.gd — SEUL PASSAGE entre la donnee inerte et la logique pure
# (lignes content.single_passage, content.additive_third_map).
#
# Lit le catalogue et les descripteurs de carte sous 03_WORLD/, et les REMET EN ARGUMENT
# aux fonctions pures. La logique ne va JAMAIS chercher un contenu, c'est le contenu qui
# lui est remis : ce SENS UNIQUE est exactement ce qui fait qu'ajouter une carte n'ouvre
# aucun fichier de 05_SYSTEMS.
#
# Une entree du catalogue est resolue par son champ `dossier` — AUCUNE carte n'est
# enumeree en dur ici : une entree de plus ne modifie pas ce fichier non plus.
#
# ADAPTATEUR : il consomme les systemes purs, jamais l'inverse. La CONSTRUCTION de la
# topologie ne lui appartient pas (elle appartient a maze) : il fournit l'ARGUMENT.
extends RefCounted

const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")

const CHEMIN_CATALOGUE := "res://03_WORLD/rules/level_catalog/catalog.json"
const DOSSIER_NIVEAUX := "res://03_WORLD/levels/"
const NOM_DESCRIPTEUR := "/level.json"
const CLE_CADENCE := "cadence_fantome"
const CLE_DOSSIER := "dossier"
const INDEX_ABSENT: int = -1

# Cache de lecture : une meme execution ne relit pas dix fois le meme fichier. Le cache
# ne change AUCUNE valeur — il evite un cout, il n'introduit aucun etat de jeu.
static var _cache: Dictionary = {}


# Lecture JSON. Un fichier absent ou illisible rend un dictionnaire VIDE : le refus est
# une valeur de retour, jamais une exception ni un bruit dans la sortie de l'oracle.
static func lire_json(chemin: String) -> Dictionary:
	if _cache.has(chemin):
		return _cache[chemin]
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return {}
	var texte: String = f.get_as_text()
	f.close()
	var lecteur := JSON.new()
	if lecteur.parse(texte) != OK:
		return {}
	var brut = lecteur.data
	if brut == null or not (brut is Dictionary):
		return {}
	_cache[chemin] = brut
	return brut


static func catalogue() -> Dictionary:
	return lire_json(CHEMIN_CATALOGUE)


# Entrees du catalogue, dans l'ORDRE DECLARE par le fichier. L'ordre et le nombre de
# cartes se LISENT ici et nulle part ailleurs.
static func entrees() -> Array:
	var cat: Dictionary = catalogue()
	if not cat.has("niveaux") or not (cat["niveaux"] is Array):
		return []
	return cat["niveaux"]


static func nb_niveaux() -> int:
	return entrees().size()


static func entree(index: int) -> Dictionary:
	var liste: Array = entrees()
	if index < 0 or index >= liste.size():
		return {}
	return liste[index]


# Nom du dossier de niveau a l'index donne. Chaine VIDE hors bornes.
static func dossier(index: int) -> String:
	var e: Dictionary = entree(index)
	if not e.has(CLE_DOSSIER):
		return ""
	return String(e[CLE_DOSSIER])


# Parametre de progression DECLARE pour ce niveau. 0 si absent : ghost_movement
# retombera sur le repli declare dans le bloc de parametres.
static func cadence(index: int) -> int:
	var e: Dictionary = entree(index)
	if not e.has(CLE_CADENCE):
		return 0
	return int(e[CLE_CADENCE])


# DESCRIPTEUR d'une carte, resolu par le NOM DE DOSSIER lu dans le catalogue — jamais
# par une liste de cartes ecrite ici. C'est la propriete qui fait tomber a 0 le nombre
# de fichiers de logique touches par l'ajout d'une troisieme carte.
static func descripteur_du_dossier(nom_dossier: String) -> Dictionary:
	if nom_dossier == "":
		return {}
	return lire_json(DOSSIER_NIVEAUX + nom_dossier + NOM_DESCRIPTEUR)


static func descripteur(index: int) -> Dictionary:
	return descripteur_du_dossier(dossier(index))


# Descripteur du PREMIER niveau du catalogue — le point d'entree normal.
static func descripteur_classique() -> Dictionary:
	return descripteur(0)


# Index du niveau portant l'identifiant donne, INDEX_ABSENT sinon. Resolution par
# lecture du catalogue, sans aucune carte citee dans ce fichier.
static func index_du_dossier(nom_dossier: String) -> int:
	var liste: Array = entrees()
	for i in range(liste.size()):
		if String(liste[i].get(CLE_DOSSIER, "")) == nom_dossier:
			return i
	return INDEX_ABSENT


# Valeurs du parametre de progression sur TOUS les niveaux embarques, dans l'ordre du
# catalogue : c'est la distribution dont on mesure qu'elle porte au moins deux valeurs
# distinctes.
static func cadences_declarees() -> Array:
	var sortie: Array = []
	for i in range(nb_niveaux()):
		sortie.append(cadence(i))
	return sortie


static func valeurs_distinctes(valeurs: Array) -> int:
	var vues: Array = []
	for v in valeurs:
		if not vues.has(v):
			vues.append(v)
	return vues.size()


# Champs obligatoires manquants du descripteur a l'index donne — la convention est lue
# dans map_schema, jamais redecrite ici.
static func champs_manquants(index: int) -> Array:
	return Schema.champs_manquants(descripteur(index))
