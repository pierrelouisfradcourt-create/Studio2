# map_schema.gd — CONVENTION de lecture d'une carte (ligne schema.map_convention).
#
# La convention vit dans la LOGIQUE, les instances vivent dans la DONNEE : ce module
# connait la legende fermee des symboles et les champs obligatoires d'un descripteur,
# et il ne connait AUCUNE carte. Il ne va chercher aucun fichier — le descripteur lui
# est REMIS EN ARGUMENT par content_provider.
#
# Logique PURE : RefCounted, aucune scene, aucun noeud, aucune horloge, aucun alea,
# aucune I/O. Feuille du graphe : ne depend d'aucun autre systeme.
extends RefCounted

# Vocabulaire ferme des types de case. Source UNIQUE : maze en fait son alias.
enum Type { MUR, COULOIR, MAISON, TUNNEL }

# LEGENDE FERMEE. Un symbole absent de cette table est un symbole INCONNU : il se
# constate (symboles_inconnus) au lieu de se deviner.
#   '#' et ' ' -> MUR (le vide hors labyrinthe est infranchissable, comme un mur)
#   '.'        -> COULOIR portant une pastille ordinaire
#   'o'        -> COULOIR portant une super-pastille
#   '_'        -> COULOIR sans collectible
#   'H'        -> MAISON (interieur de la maison centrale)
#   '-'        -> MAISON (porte de la maison centrale)
#   'T'        -> TUNNEL (couloir de bouclage, sans collectible)
const LEGENDE: Dictionary = {
	"#": Type.MUR,
	" ": Type.MUR,
	".": Type.COULOIR,
	"o": Type.COULOIR,
	"_": Type.COULOIR,
	"H": Type.MAISON,
	"-": Type.MAISON,
	"T": Type.TUNNEL,
}

const SYMBOLE_PASTILLE := "."
const SYMBOLE_SUPER := "o"
const SYMBOLE_MUR := "#"
const SYMBOLE_VIDE := " "
const SYMBOLE_TUNNEL := "T"

# Champs qu'un descripteur DOIT porter. Aucun defaut n'est invente a leur place.
const CHAMPS_OBLIGATOIRES: Array = [
	"id", "nom", "plan",
	"depart_pacman", "depart_direction",
	"maison_centre", "sortie_maison", "places_maison",
]

const LIGNE_ABSENTE: int = -1


static func symbole_connu(c: String) -> bool:
	return LEGENDE.has(c)


# Type d'un symbole. Un symbole hors legende vaut MUR : la lecture ne leve jamais, elle
# refuse. Le REFUS explicite est le travail de map_validator, pas de la convention.
static func type_du_symbole(c: String) -> int:
	if not LEGENDE.has(c):
		return Type.MUR
	return LEGENDE[c]


static func porte_pastille(c: String) -> bool:
	return c == SYMBOLE_PASTILLE


static func porte_super(c: String) -> bool:
	return c == SYMBOLE_SUPER


# Champs obligatoires ABSENTS du descripteur, dans l'ordre declare (jamais l'ordre d'un
# Dictionary).
static func champs_manquants(desc: Dictionary) -> Array:
	var sortie: Array = []
	for champ in CHAMPS_OBLIGATOIRES:
		if not desc.has(champ):
			sortie.append(champ)
	return sortie


# Symboles du plan absents de la legende, sans doublon, dans l'ordre de lecture.
static func symboles_inconnus(plan: Array) -> Array:
	var sortie: Array = []
	for y in range(plan.size()):
		var ligne: String = plan[y]
		for x in range(ligne.length()):
			var c: String = ligne.substr(x, 1)
			if not symbole_connu(c) and not sortie.has(c):
				sortie.append(c)
	return sortie


static func plan_rectangulaire(plan: Array) -> bool:
	if plan.is_empty():
		return false
	var l: int = String(plan[0]).length()
	if l <= 0:
		return false
	for ligne in plan:
		if String(ligne).length() != l:
			return false
	return true


static func largeur(plan: Array) -> int:
	if plan.is_empty():
		return 0
	return String(plan[0]).length()


static func hauteur(plan: Array) -> int:
	return plan.size()


# Ligne de BOUCLAGE : la premiere ligne portant le symbole de tunnel. LIGNE_ABSENTE si
# la carte n'en porte aucune — la valeur est DERIVEE du plan, jamais declaree deux fois.
static func ligne_tunnel(plan: Array) -> int:
	for y in range(plan.size()):
		if String(plan[y]).find(SYMBOLE_TUNNEL) != -1:
			return y
	return LIGNE_ABSENTE


static func _ligne_vide(ligne: String) -> bool:
	for x in range(ligne.length()):
		if ligne.substr(x, 1) != SYMBOLE_VIDE:
			return false
	return true


# Bornes de la ZONE JOUABLE : premiere et derniere lignes portant autre chose que du
# vide. Les rangees de bandeau (vide pur) sont hors labyrinthe. DERIVEES, non declarees.
static func premiere_ligne_jouable(plan: Array) -> int:
	for y in range(plan.size()):
		if not _ligne_vide(String(plan[y])):
			return y
	return LIGNE_ABSENTE


static func derniere_ligne_jouable(plan: Array) -> int:
	var trouve: int = LIGNE_ABSENTE
	for y in range(plan.size()):
		if not _ligne_vide(String(plan[y])):
			trouve = y
	return trouve


# Table PLATE des types, indexee y * largeur + x. C'est la carte UTILISABLE construite a
# partir du descripteur recu : une donnee, pas un comportement.
static func table_des_types(plan: Array) -> PackedByteArray:
	var l: int = largeur(plan)
	var h: int = hauteur(plan)
	var t := PackedByteArray()
	t.resize(l * h)
	for y in range(h):
		var ligne: String = plan[y]
		for x in range(l):
			t[y * l + x] = type_du_symbole(ligne.substr(x, 1))
	return t


# Lecture d'un couple [x, y] du descripteur en case de grille. Une valeur malformee rend
# la case (0, 0) : le refus appartient a map_validator, pas a la lecture.
static func vecteur(brut) -> Vector2i:
	if not (brut is Array) or brut.size() != 2:
		return Vector2i(0, 0)
	return Vector2i(int(brut[0]), int(brut[1]))


static func vecteurs(brut) -> Array:
	var sortie: Array = []
	if not (brut is Array):
		return sortie
	for v in brut:
		sortie.append(vecteur(v))
	return sortie
