# boot.gd — amorcage de l'application (lignes runtime.boot_window,
# runtime.title_boot_no_game).
#
# V2 : l'application amorce SUR L'ECRAN TITRE — AUCUNE partie n'est construite au
# demarrage. Consequence mecanique : le compteur de ticks de partie vaut 0 parce
# qu'aucune partie n'existe, PAS parce qu'un rendu la masque.
#
# Zero asset importe : aucune image, aucune police, aucun son n'est charge.
extends RefCounted

const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")

# Graine de determinisme du jeu lance a la main (pas un parametre d'equilibrage).
const GRAINE_INITIALE: int = Shell.GRAINE_INITIALE


# SESSION d'amorcage : ecran titre, aucune partie.
static func session_initiale() -> Dictionary:
	return Shell.session_initiale()


# Carte du premier niveau, VALIDEE. Sert a dimensionner la fenetre — pas a lancer une
# partie : l'affichage a besoin d'une taille, le joueur n'a encore rien demande.
static func carte_de_reference():
	return Shell.carte(0)


# Etat de partie construit a la demande explicite du joueur (activation de Jouer).
static func etat_initial() -> Object:
	var sess: Dictionary = Shell.activer_titre(session_initiale(), 0)["session"]
	return sess["partie"]


# ENVELOPPE de rendu = la fenetre. Elle est definie par la carte de reference, et elle
# NE CHANGE PAS d'une carte a l'autre (V3, cause racine P4) : ce sont les cartes qui s'y
# adaptent, en taille de case derivee et en position centree.
static func largeur_fenetre() -> int:
	return MazeView.largeur_enveloppe(carte_de_reference())


static func hauteur_fenetre() -> int:
	return MazeView.hauteur_enveloppe(carte_de_reference())


# La fenetre declaree contient-elle la grille entiere sans defilement ?
static func fenetre_contient_grille(largeur: int, hauteur: int) -> bool:
	return largeur >= largeur_fenetre() and hauteur >= hauteur_fenetre()


# Une carte QUELCONQUE tient-elle dans l'enveloppe declaree ? Le debordement attendu vaut
# exactement 0 sur les deux axes, pour N cartes et pas seulement pour deux.
static func carte_tient_dans_l_enveloppe(carte) -> bool:
	return MazeView.debordement(carte, largeur_fenetre(), hauteur_fenetre()) == Vector2i(0, 0)
