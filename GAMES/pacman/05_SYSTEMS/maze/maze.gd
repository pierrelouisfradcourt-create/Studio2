# maze.gd — TOPOLOGIE d'une carte, construite par LECTURE d'un descripteur RECU EN
# ARGUMENT (lignes maze.from_descriptor, maze.derived_dimensions).
#
# V2 : ce fichier ne porte PLUS de plan litteral ni de constante de carte. Une instance
# EST une carte ; le plan, les positions de depart et les dimensions viennent du
# descripteur. C'est la premiere des quatre causes mesurees de la baseline V1 qui tombe.
# Les grandeurs autrefois figees en constantes (largeur, hauteur, ligne de bouclage,
# premiere et derniere lignes jouables, coins) sont DERIVEES du plan.
#
# Logique PURE : RefCounted, aucune scene, aucun noeud, aucune horloge, aucun alea,
# aucune I/O. Ne depend que de map_schema (la convention), jamais de 03_WORLD.
extends RefCounted

const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")

const CHEMIN := "res://05_SYSTEMS/maze/maze.gd"

# Vocabulaire ferme des types de case : ALIAS de la source unique (map_schema), jamais
# une seconde declaration qui pourrait diverger.
const Type = Schema.Type

# --- Vocabulaire ferme de directions, ORDRE FIXE et DECLARE (haut, gauche, bas, droite).
# C'est cet ordre — et lui seul — qui departage les egalites, pour le joueur comme pour
# les fantomes : l'enumeration ne depend jamais de l'ordre d'un Dictionary.
# Ces valeurs ne decrivent AUCUNE carte : elles restent des constantes de classe.
const HAUT := Vector2i(0, -1)
const GAUCHE := Vector2i(-1, 0)
const BAS := Vector2i(0, 1)
const DROITE := Vector2i(1, 0)
const AUCUNE := Vector2i(0, 0)
const DIRECTIONS: Array = [HAUT, GAUCHE, BAS, DROITE]

# --- Champs d'INSTANCE : tout ce qui decrit UNE carte ---
var ID: String = ""
var NOM: String = ""
var PLAN: Array = []
var LARGEUR: int = 0
var HAUTEUR: int = 0
var LIGNE_TUNNEL: int = Schema.LIGNE_ABSENTE
var LABY_PREMIERE_LIGNE: int = Schema.LIGNE_ABSENTE
var LABY_DERNIERE_LIGNE: int = Schema.LIGNE_ABSENTE
var DEPART_PACMAN: Vector2i = Vector2i(0, 0)
var DEPART_DIRECTION: Vector2i = GAUCHE
var MAISON_CENTRE: Vector2i = Vector2i(0, 0)
var SORTIE_MAISON: Vector2i = Vector2i(0, 0)
var PLACES_MAISON: Array = []
var COINS: Array = []

# Table des types, construite UNE fois a la lecture du descripteur. Sans elle, chaque
# interrogation de case decoupe une sous-chaine — le parcours en largeur du bot en fait
# des centaines de milliers par partie.
var _types: PackedByteArray = PackedByteArray()


# Construit la carte a partir du descripteur RECU. Aucun fichier n'est ouvert ici : la
# logique ne va JAMAIS chercher un contenu, il lui est remis.
static func depuis_descripteur(desc: Dictionary) -> Object:
	var c = load(CHEMIN).new()
	c.ID = String(desc.get("id", ""))
	c.NOM = String(desc.get("nom", ""))
	c.PLAN = desc.get("plan", []) as Array
	c.LARGEUR = Schema.largeur(c.PLAN)
	c.HAUTEUR = Schema.hauteur(c.PLAN)
	c.LIGNE_TUNNEL = Schema.ligne_tunnel(c.PLAN)
	c.LABY_PREMIERE_LIGNE = Schema.premiere_ligne_jouable(c.PLAN)
	c.LABY_DERNIERE_LIGNE = Schema.derniere_ligne_jouable(c.PLAN)
	c.DEPART_PACMAN = Schema.vecteur(desc.get("depart_pacman", null))
	c.DEPART_DIRECTION = Schema.vecteur(desc.get("depart_direction", null))
	c.MAISON_CENTRE = Schema.vecteur(desc.get("maison_centre", null))
	c.SORTIE_MAISON = Schema.vecteur(desc.get("sortie_maison", null))
	c.PLACES_MAISON = Schema.vecteurs(desc.get("places_maison", []))
	# Coins de reference, dans l'ordre des fantomes (rouge, rose, cyan, orange) :
	# DERIVES des dimensions, donc justes sur une carte de toute taille.
	c.COINS = [
		Vector2i(c.LARGEUR - 1, 0),
		Vector2i(0, 0),
		Vector2i(c.LARGEUR - 1, c.HAUTEUR - 1),
		Vector2i(0, c.HAUTEUR - 1),
	]
	c._types = Schema.table_des_types(c.PLAN)
	return c


# Deux cartes sont la MEME carte si elles portent le meme identifiant declare : c'est ce
# qui rend comparable l'etat de partie de part et d'autre d'une bascule de niveau.
func meme_carte(autre) -> bool:
	if autre == null:
		return false
	return ID == autre.ID


func dans_grille(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < LARGEUR and p.y >= 0 and p.y < HAUTEUR


# Zone de LABYRINTHE JOUABLE, distincte de la grille d'ECRAN. Les rangees de bandeau
# portent le type `mur` faute de cinquieme valeur au vocabulaire ferme ; ce predicat
# existe pour qu'aucune fixture de bord, de coin ou de cul-de-sac ne les confonde avec
# un mur de labyrinthe.
func dans_labyrinthe(p: Vector2i) -> bool:
	return dans_grille(p) and p.y >= LABY_PREMIERE_LIGNE and p.y <= LABY_DERNIERE_LIGNE


# Type de la case (ligne maze.topology) : lisible pour CHAQUE case de la grille.
func type_case(p: Vector2i) -> int:
	if not dans_grille(p):
		return Type.MUR
	return _types[p.y * LARGEUR + p.x]


# Symbole brut du plan — lu par pellets pour poser les collectibles. Le descripteur
# reste la source unique : personne ne redecrit la grille, on la relit.
func symbole(p: Vector2i) -> String:
	if not dans_grille(p):
		return Schema.SYMBOLE_MUR
	return String(PLAN[p.y]).substr(p.x, 1)


# Praticabilite (ligne maze.walkable) : consommee IDENTIQUEMENT par le joueur et les
# fantomes. La maison n'est pas praticable — elle appartient a ghost_house.
func praticable(p: Vector2i) -> bool:
	var t: int = type_case(p)
	return t == Type.COULOIR or t == Type.TUNNEL


# Bouclage de tunnel (ligne maze.tunnel_wrap) : la colonne passe d'une extremite a
# l'autre, la ligne est INCHANGEE. Applique identiquement a toutes les entites.
func boucler(p: Vector2i) -> Vector2i:
	if p.x < 0:
		return Vector2i(LARGEUR - 1, p.y)
	if p.x >= LARGEUR:
		return Vector2i(0, p.y)
	return p


# Case atteinte depuis `p` dans la direction `d`, bouclage applique.
func case_suivante(p: Vector2i, d: Vector2i) -> Vector2i:
	return boucler(p + d)


# Voisins praticables (ligne maze.neighbours) dans l'ORDRE FIXE declare par DIRECTIONS.
func voisins_praticables(p: Vector2i) -> Array:
	var sortie: Array = []
	for d in DIRECTIONS:
		var v: Vector2i = case_suivante(p, d)
		if praticable(v):
			sortie.append(v)
	return sortie


# Directions praticables depuis `p`, meme ordre fixe.
func directions_praticables(p: Vector2i) -> Array:
	var sortie: Array = []
	for d in DIRECTIONS:
		if praticable(case_suivante(p, d)):
			sortie.append(d)
	return sortie


# Index plat d'une case (y * LARGEUR + x) : sert aux tableaux plats de collectibles et
# de distances. Deterministe, jamais un ordre de Dictionary.
func index_de(p: Vector2i) -> int:
	return p.y * LARGEUR + p.x


func case_de(i: int) -> Vector2i:
	return Vector2i(i % LARGEUR, i / LARGEUR)


func nb_cases() -> int:
	return LARGEUR * HAUTEUR


# Distance de grille de Manhattan — mesure UNIQUE partagee par le ciblage et les
# preuves. Ne depend d'AUCUNE carte : reste statique.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
