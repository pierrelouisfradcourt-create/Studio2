# palette.gd — DESCRIPTEUR DE PALETTE UNIQUE (ligne palette.single_descriptor).
#
# Consomme par TOUS les ecrans — titre, partie, pause, controles, options, fin. Changer
# ce SEUL module change l'apparence de tous les ecrans a la fois : c'est l'UNICITE DU
# LIEU qui rend l'identite mesurable au lieu d'etre une appreciation. Le comptage des
# litteraux de couleur situes HORS de ce fichier vaut exactement 0.
#
# Ne connait AUCUN ecran ; ce sont les ecrans qui la lisent. Feuille du graphe.
extends RefCounted

# --- Fond et structure du labyrinthe ---
const MUR := Color(0.12, 0.16, 0.62)
const COULOIR := Color(0.02, 0.02, 0.06)
const MAISON := Color(0.35, 0.35, 0.45)
const TUNNEL := Color(0.02, 0.06, 0.14)

# --- Identite visuelle procedurale (V3, cause racine P2) --------------------------
# Aucun fichier n'entre dans le depot : l'identite est portee par des COULEURS et des
# FORMES calculees. Ces entrees sont ce qui separe un mur DESSINE d'un rectangle plein.
# ARETE : liseré clair au bord interieur d'un mur — c'est lui qui donne au labyrinthe
# son trace, la ou un aplat ne donnait qu'une masse.
const MUR_ARETE := Color(0.36, 0.46, 1.0)
# CREUX : interieur du mur, plus sombre que son arete. Le couple arete/creux fabrique
# un relief sans aucune texture.
const MUR_CREUX := Color(0.07, 0.09, 0.38)
# HORS-JEU : ce qui entoure le labyrinthe quand la carte ne remplit pas l'enveloppe.
# Distinct du couloir : sans cela, la bordure se lirait comme une zone jouable.
const HORS_JEU := Color(0.0, 0.0, 0.02)

# --- Entites ---
const PASTILLE := Color(0.98, 0.85, 0.66)
# La super-pastille a sa PROPRE couleur : sa taille seule ne suffisait pas a la nommer.
const SUPER_PASTILLE := Color(1.0, 0.98, 0.86)
# Halo des collectibles et du joueur — une couleur d'ECLAT, appliquee en transparence.
const LUEUR := Color(1.0, 0.92, 0.55)
const PACMAN := Color(1.0, 0.92, 0.0)
const FANTOME_EFFRAYE := Color(0.15, 0.2, 0.95)
# CLIGNOTEMENT de fin d'effroi : la seconde teinte, alternee, qui annonce la reprise.
const FANTOME_EFFRAYE_FIN := Color(0.92, 0.94, 1.0)
# Yeux des fantomes : ce sont eux qui donnent une silhouette VIVANTE et disent, sans
# texte, dans quelle direction le fantome regarde.
const FANTOME_OEIL := Color(0.97, 0.97, 1.0)
const FANTOME_PUPILLE := Color(0.08, 0.08, 0.35)
# Quatre couleurs DEUX A DEUX DIFFERENTES, dans l'ordre nominatif des fantomes.
const FANTOMES: Array = [
	Color(1.0, 0.0, 0.0),
	Color(1.0, 0.72, 0.87),
	Color(0.0, 1.0, 1.0),
	Color(1.0, 0.72, 0.22),
]

# --- Bandeau d'etat de poursuite ---
const ETAT_DISPERSION := Color(0.55, 0.75, 1.0)
const ETAT_POURSUITE := Color(1.0, 0.45, 0.35)
const ETAT_EFFRAYE := Color(0.45, 0.55, 1.0)

# --- Ecrans de coquille (titre, pause, controles, options, fin) ---
const FOND_ECRAN := Color(0.02, 0.02, 0.08)
# VOILE MODAL (V4, cause racine P2) : l'ecran de fin se lisait PAR-DESSUS le labyrinthe,
# sans aucune couche entre les deux. Ce n'est PAS FOND_ECRAN : celui-la est opaque et
# efface tout, celui-ci garde la partie visible DERRIERE, assombrie. C'est le canal alpha
# qui porte la difference, et c'est lui que la preuve mesure.
const FOND_MODAL := Color(0.01, 0.01, 0.05, 0.90)
const TEXTE := Color(0.92, 0.92, 0.98)
const TEXTE_SECONDAIRE := Color(0.62, 0.66, 0.80)
# V3 : la selection portait EXACTEMENT la teinte du joueur. Deux noms pour une meme
# couleur, donc une identite que les noms promettaient sans la tenir — et, a l'ecran, un
# surlignage de menu indistinguable du personnage. Teinte VOISINE mais DISTINCTE.
const SELECTION := Color(1.0, 0.78, 0.18)
const ACCENT := Color(0.35, 0.85, 0.75)
const DASH_PRET := Color(0.35, 0.95, 0.55)
const DASH_RECHARGE := Color(0.55, 0.55, 0.62)

# NOMS declares de toutes les entrees de la palette : l'enumeration existe pour que le
# comptage « une seule source de couleurs » soit verifiable, pas seulement affirme.
const NOMS: Array = [
	"MUR", "COULOIR", "MAISON", "TUNNEL",
	"MUR_ARETE", "MUR_CREUX", "HORS_JEU",
	"PASTILLE", "SUPER_PASTILLE", "LUEUR", "PACMAN", "FANTOME_EFFRAYE", "FANTOMES",
	"FANTOME_EFFRAYE_FIN", "FANTOME_OEIL", "FANTOME_PUPILLE",
	"ETAT_DISPERSION", "ETAT_POURSUITE", "ETAT_EFFRAYE",
	"FOND_ECRAN", "FOND_MODAL", "TEXTE", "TEXTE_SECONDAIRE", "SELECTION", "ACCENT",
	"DASH_PRET", "DASH_RECHARGE",
]


static func couleurs() -> Array:
	var sortie: Array = [
		MUR, COULOIR, MAISON, TUNNEL, MUR_ARETE, MUR_CREUX, HORS_JEU,
		PASTILLE, SUPER_PASTILLE, LUEUR, PACMAN, FANTOME_EFFRAYE,
		FANTOME_EFFRAYE_FIN, FANTOME_OEIL, FANTOME_PUPILLE,
		ETAT_DISPERSION, ETAT_POURSUITE, ETAT_EFFRAYE,
		FOND_ECRAN, FOND_MODAL, TEXTE, TEXTE_SECONDAIRE, SELECTION, ACCENT,
		DASH_PRET, DASH_RECHARGE,
	]
	for c in FANTOMES:
		sortie.append(c)
	return sortie


# LUMINANCE perceptuelle d'une couleur — mesure UNIQUE du contraste, partagee par les
# preuves. Sans elle, « le mur se distingue du couloir » resterait une appreciation.
static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func ecart_de_luminance(a: Color, b: Color) -> float:
	return absf(luminance(a) - luminance(b))


# Nombre de PAIRES DE COULEURS IDENTIQUES dans le descripteur. Une palette qui repete
# une teinte sous deux noms n'a pas l'identite que ses noms promettent : la valeur
# attendue vaut exactement 0.
static func paires_identiques() -> int:
	var liste: Array = couleurs()
	var n: int = 0
	for i in range(liste.size()):
		for j in range(i + 1, liste.size()):
			if liste[i] == liste[j]:
				n += 1
	return n


# Les quatre couleurs de fantomes sont-elles deux a deux differentes ?
static func fantomes_distincts() -> bool:
	for i in range(FANTOMES.size()):
		for j in range(i + 1, FANTOMES.size()):
			if FANTOMES[i] == FANTOMES[j]:
				return false
	return true


static func couleur_fantome(index: int) -> Color:
	if index < 0 or index >= FANTOMES.size():
		return TEXTE
	return FANTOMES[index]
