# end_screen.gd — ecran de fin nommant l'issue, le score final ET LES SUITES OFFERTES
# (ligne render.end_screen).
#
# V3, cause racine P5 : la logique pure avait DEJA tout ce qu'il faut — App.Etat.FIN,
# vers_partie, vers_titre, et session.carte_terminee qui traite le catalogue epuise. Ce
# qui manquait etait ici : cet ecran ne rendait qu'un TEXTE D'ISSUE, sans aucun choix, et
# annoncait des touches ([R], [Echap]) au lieu d'offrir des entrees. Une fin de partie
# sans entree activable est une impasse, quel que soit l'etat que la logique atteint.
#
# Les CHOIX vivent donc dans l'adaptateur, pas dans 05_SYSTEMS : aucun fichier de logique
# n'est touche pour offrir une suite. Le VOCABULAIRE D'ACTION, lui, est REUTILISE de
# menu_model — un second vocabulaire d'actions pourrait diverger du premier.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

const MESSAGE_GAGNE := "LABYRINTHE VIDE — GAGNE"
const MESSAGE_PERDU := "PLUS DE VIES — PERDU"

# --- CLIN D'OEIL DE VICTOIRE SANS AIDE (V6, demande Pierre) -------------------------
# Il apparait a la SEULE condition CONJONCTIVE : partie GAGNEE, mode du DEFI, dash
# DESACTIVE. C'est-a-dire : le joueur a gagne sans aucune des deux assistances que le jeu
# propose. Les trois conditions sont exigees ensemble ; il manque l'une, il n'apparait pas.
#
# Message FICTIF et NON CIBLE : il ne parle que des fantomes du jeu, ne vise aucune
# personne, aucun groupe, aucune organisation reelle.
#
# CE QU'IL NE FAIT PAS, ET C'EST LA CONTRAINTE PRINCIPALE : il ne touche NI la condition
# de victoire, NI les transitions, NI les choix Rejouer / Menu principal. Il s'AJOUTE a
# l'affichage, en derniere ligne, et rien d'autre du recap ne bouge.
const CLIN_D_OEIL_SANS_AIDE := "Les quatre fantomes demandent une revanche : aucune aide, et ils ont perdu."

# --- SUITES OFFERTES A LA FIN D'UNE PARTIE ----------------------------------------
enum Choix { REJOUER, MENU_PRINCIPAL }
const ENTREES: Array = [Choix.REJOUER, Choix.MENU_PRINCIPAL]
const LIBELLES: Array = ["Rejouer", "Menu principal"]

# Mention de navigation. Elle NOMME les commandes du vocabulaire d'intentions, pas des
# touches : les touches vivent dans la table de liaisons, l'ecran de controles les nomme.
const MENTION_RELANCE := "Haut / Bas : choisir     Valider : confirmer"


# --- COUCHE MODALE (V4, cause racine P2) ------------------------------------------
# DEFAUT MESURE (playtest Pierre) : l'ecran de fin SE MELANGEAIT A LA CARTE. Deux causes
# distinctes, toutes deux ici :
#   (1) aucune couche entre le labyrinthe et le texte — le recap se lisait sur les murs ;
#   (2) DEUX surfaces de texte au meme endroit (le recap de fin ET l'ecran de coquille
#       FIN), donc deux blocs superposes. La seconde est traitee par runtime_loop.
#
# La couche est declaree ICI, avec la geometrie de la zone de texte qu'elle doit
# contenir : le voile et le label sont poses depuis LA MEME declaration, ce qui interdit
# a l'un de deriver de l'autre. Aucun litteral de couleur — la teinte vient de la palette.
const OPACITE_MINIMALE: float = 0.75
# Lignes du recap ORDINAIRE : issue, score, deux choix, mention de navigation.
const LIGNES_RECAP: int = 5
# V6 : une SIXIEME ligne existe dans le seul cas du clin d'oeil de victoire sans aide. La
# zone de texte est dimensionnee sur ce MAXIMUM, jamais sur le cas ordinaire : un voile
# trop court laisserait la derniere ligne se lire sur le labyrinthe — exactement le defaut
# corrige en V4.
const LIGNES_RECAP_MAX: int = LIGNES_RECAP + 1
const HAUTEUR_LIGNE: int = 28
# Hauteur de la zone de texte du recap, DERIVEE du nombre de lignes maximal : une hauteur
# ecrite a la main pourrait diverger du texte qu'elle doit contenir.
const HAUTEUR_TEXTE: int = HAUTEUR_LIGNE * LIGNES_RECAP_MAX
# Ecart de luminance exige entre le voile et le texte pose dessus.
const CONTRASTE_MINIMAL: float = 0.5


static func est_actif(statut: int) -> bool:
	return Status.est_terminal(statut)


static func fond_modal() -> Color:
	return Palette.FOND_MODAL


# OPACITE du voile : c'est CETTE grandeur, et non la presence d'un rectangle, qui
# distingue une couche modale d'un simple cadre. Un voile transparent laisserait le
# labyrinthe traverser le texte exactement comme avant.
static func opacite_modale() -> float:
	return Palette.FOND_MODAL.a


static func couche_opaque() -> bool:
	return opacite_modale() >= OPACITE_MINIMALE


# La partie reste-t-elle VISIBLE derriere le voile ? Un voile totalement opaque ne serait
# plus une couche modale mais un ecran de remplacement.
static func partie_visible_derriere() -> bool:
	return opacite_modale() < 1.0


# CONTRASTE entre le voile et le texte pose dessus — mesure unique de la palette.
static func contraste_texte() -> float:
	return Palette.ecart_de_luminance(Palette.FOND_MODAL, Palette.TEXTE)


static func texte_lisible_sur_le_voile() -> bool:
	return contraste_texte() >= CONTRASTE_MINIMAL


# VOILE : il couvre TOUTE l'enveloppe de rendu. Une couche partielle laisserait le
# labyrinthe affleurer au bord du texte, ce qui est le defaut d'origine.
static func rect_modal(largeur: int, hauteur: int) -> Rect2:
	return Rect2(0.0, 0.0, float(largeur), float(hauteur))


# ZONE DE TEXTE du recap, centree dans l'enveloppe. runtime_loop pose le label a CETTE
# geometrie : le voile et le texte ne peuvent pas diverger.
static func rect_texte(largeur: int, hauteur: int) -> Rect2:
	var h: float = float(HAUTEUR_TEXTE)
	return Rect2(0.0, (float(hauteur) - h) / 2.0, float(largeur), h)


# Le voile CONTIENT-IL la zone de texte ? Sans cette inclusion, une partie du recap se
# lirait encore sur le labyrinthe.
static func voile_contient_le_texte(largeur: int, hauteur: int) -> bool:
	return rect_modal(largeur, hauteur).encloses(rect_texte(largeur, hauteur))


# Texte d'issue : deux issues, deux textes DIFFERENTS.
static func message(statut: int) -> String:
	if statut == State.Statut.GAGNE:
		return MESSAGE_GAGNE
	if statut == State.Statut.PERDU:
		return MESSAGE_PERDU
	return ""


# GARDE POSITIVE, meme forme que menu_model : l'intervalle valide est enonce, et le
# tableau n'est lu que dedans. GDScript accepterait un index negatif en comptant depuis
# la fin — libelle(-1) rendrait « Menu principal » au lieu de rien.
static func libelle(choix: int) -> String:
	if choix >= 0 and choix < LIBELLES.size():
		return LIBELLES[choix]
	return ""


# EFFET d'un choix : etat d'application vise ET action demandee, dans le MEME vocabulaire
# que les menus titre et pause. Deux choix, deux effets DIFFERENTS.
static func effet(choix: int) -> Dictionary:
	if choix == Choix.REJOUER:
		return {"etat": App.Etat.PARTIE, "action": Menu.ACTION_NOUVELLE_PARTIE}
	if choix == Choix.MENU_PRINCIPAL:
		return {"etat": App.Etat.TITRE, "action": Menu.ACTION_MENU_PRINCIPAL}
	return {"etat": App.Etat.FIN, "action": Menu.ACTION_AUCUNE}


static func effets() -> Array:
	var sortie: Array = []
	for c in ENTREES:
		sortie.append(effet(c))
	return sortie


# Nombre de choix SANS EFFET OBSERVABLE — meme mesure que pour les autres menus, avec le
# meme compteur : la valeur attendue vaut exactement 0. C'est LE chiffre qui distingue
# « une fin offrant des suites » de « une fin affichant des suites ».
static func choix_sans_effet() -> int:
	return Menu.compter_sans_effet(effets(), App.Etat.FIN)


# Lignes de choix, selection MARQUEE — meme convention d'affichage que les autres ecrans.
static func lignes(selection: int) -> Array:
	var sortie: Array = []
	for i in range(LIBELLES.size()):
		var marque: String = "> " if i == selection else "  "
		sortie.append(marque + String(LIBELLES[i]))
	return sortie


# Recapitulatif de fin, pris du SEUL releve observable : le score final affiche est
# EGAL au score de l'etat. Les SUITES sont rendues avec lui : l'ecran de fin n'annonce
# plus une relance, il la propose.
static func recap(releve: Dictionary, selection: int = 0) -> String:
	if not est_actif(releve["statut"]):
		return ""
	var texte: String = "%s\nSCORE FINAL %d\n%s\n%s" % [
		message(releve["statut"]),
		releve["score"],
		"\n".join(lignes(selection)),
		MENTION_RELANCE,
	]
	# Le clin d'oeil s'AJOUTE en fin de recap. Il ne remplace rien et ne reordonne rien :
	# les deux choix et leur mention sont deja poses au-dessus, intacts.
	var suffixe: String = clin_d_oeil(releve)
	if suffixe != "":
		texte += "\n" + suffixe
	return texte


# --- CLIN D'OEIL : trois conditions CONJONCTIVES, lues sur le SEUL releve observable ---
# Le releve porte deja les trois faits (`statut`, `mode_jeu`, `dash_actif`) : cet ecran ne
# va donc rien chercher ailleurs et ne peut pas voir un etat different de celui qui est
# affiche. Un releve INCOMPLET (cle absente) ne declenche RIEN — le repli est le silence,
# jamais l'apparition.
static func victoire_sans_aide(releve: Dictionary) -> bool:
	if int(releve.get("statut", -1)) != State.Statut.GAGNE:
		return false
	if String(releve.get("mode_jeu", "")) != Reglages.nom(Reglages.Mode.NORMAL):
		return false
	return not bool(releve.get("dash_actif", true))


static func clin_d_oeil(releve: Dictionary) -> String:
	if not victoire_sans_aide(releve):
		return ""
	return CLIN_D_OEIL_SANS_AIDE
