# menu_model.gd — MENUS COMME DONNEE (lignes menu.title_entries, menu.pause_entries).
#
# Une entree est une LIGNE DE LISTE, jamais un libelle dessine : c'est ce qui rend
# COMPTABLE le nombre d'entrees sans effet observable. La traduction d'une activation en
# transition d'etat d'application vit ici ; l'EXISTENCE des effets appartient a app_shell.
#
# Logique PURE. Ne depend que de app_state.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")

# --- Menu TITRE : quatre entrees identifiees ---
enum Titre { JOUER, CONTROLES, OPTIONS, QUITTER }
const ENTREES_TITRE: Array = [Titre.JOUER, Titre.CONTROLES, Titre.OPTIONS, Titre.QUITTER]
const LIBELLES_TITRE: Array = ["Jouer", "Controles", "Options", "Quitter"]

# --- Menu PAUSE : cinq entrees identifiees ---
enum Pause { REPRENDRE, RECOMMENCER, CONTROLES, OPTIONS, MENU_PRINCIPAL }
const ENTREES_PAUSE: Array = [
	Pause.REPRENDRE, Pause.RECOMMENCER, Pause.CONTROLES, Pause.OPTIONS, Pause.MENU_PRINCIPAL,
]
const LIBELLES_PAUSE: Array = [
	"Reprendre", "Recommencer", "Controles", "Options", "Menu principal",
]

# Vocabulaire ferme des ACTIONS demandees a la couche qui detient la partie.
const ACTION_AUCUNE := "aucune"
const ACTION_NOUVELLE_PARTIE := "nouvelle_partie"
const ACTION_REPRENDRE := "reprendre"
const ACTION_RECOMMENCER := "recommencer"
const ACTION_MENU_PRINCIPAL := "menu_principal"
const ACTION_QUITTER := "quitter"


# GARDE POSITIVE : l'intervalle VALIDE est enonce, et le tableau n'est lu que dedans.
# GDScript accepte les index negatifs (comptes depuis la fin) : sans borne basse
# explicite, libelle_titre(-1) rendrait « Quitter » au lieu de rien. Et a l'index egal
# a la taille, une lecture hors bornes serait coercee en "" par le type de retour —
# indistinguable de ce refus. Enoncer l'intervalle rend les DEUX bornes observables.
static func libelle_titre(entree: int) -> String:
	if entree >= 0 and entree < LIBELLES_TITRE.size():
		return LIBELLES_TITRE[entree]
	return ""


# Meme garde positive, meme raison.
static func libelle_pause(entree: int) -> String:
	if entree >= 0 and entree < LIBELLES_PAUSE.size():
		return LIBELLES_PAUSE[entree]
	return ""


# Deplacement de la selection dans une liste de `taille` entrees, par pas de `delta`.
# Le parcours BOUCLE : il n'existe aucune selection hors liste.
static func deplacer(selection: int, delta: int, taille: int) -> int:
	if taille <= 0:
		return 0
	var s: int = (selection + delta) % taille
	if s < 0:
		s += taille
	return s


# EFFET d'une activation du menu titre : etat d'application vise ET action demandee.
static func effet_titre(entree: int) -> Dictionary:
	if entree == Titre.JOUER:
		return {"etat": App.Etat.PARTIE, "action": ACTION_NOUVELLE_PARTIE}
	if entree == Titre.CONTROLES:
		return {"etat": App.Etat.CONTROLES, "action": ACTION_AUCUNE}
	if entree == Titre.OPTIONS:
		return {"etat": App.Etat.OPTIONS, "action": ACTION_AUCUNE}
	if entree == Titre.QUITTER:
		return {"etat": App.Etat.TITRE, "action": ACTION_QUITTER}
	return {"etat": App.Etat.TITRE, "action": ACTION_AUCUNE}


# EFFET d'une activation du menu pause : cinq transitions DEUX A DEUX DIFFERENTES.
static func effet_pause(entree: int) -> Dictionary:
	if entree == Pause.REPRENDRE:
		return {"etat": App.Etat.PARTIE, "action": ACTION_REPRENDRE}
	if entree == Pause.RECOMMENCER:
		return {"etat": App.Etat.PARTIE, "action": ACTION_RECOMMENCER}
	if entree == Pause.CONTROLES:
		return {"etat": App.Etat.CONTROLES, "action": ACTION_AUCUNE}
	if entree == Pause.OPTIONS:
		return {"etat": App.Etat.OPTIONS, "action": ACTION_AUCUNE}
	if entree == Pause.MENU_PRINCIPAL:
		return {"etat": App.Etat.TITRE, "action": ACTION_MENU_PRINCIPAL}
	return {"etat": App.Etat.PAUSE, "action": ACTION_AUCUNE}


# Deux effets sont-ils DIFFERENTS ? Comparaison sur le couple (etat vise, action) :
# deux entrees qui menent au meme etat par la meme action sont indistinguables.
static func effets_differents(a: Dictionary, b: Dictionary) -> bool:
	return a["etat"] != b["etat"] or a["action"] != b["action"]


# Effets des entrees d'un menu, dans l'ordre declare : une DONNEE enumerable.
static func effets_titre() -> Array:
	var sortie: Array = []
	for e in ENTREES_TITRE:
		sortie.append(effet_titre(e))
	return sortie


static func effets_pause() -> Array:
	var sortie: Array = []
	for e in ENTREES_PAUSE:
		sortie.append(effet_pause(e))
	return sortie


# Nombre d'entrees SANS EFFET OBSERVABLE dans une liste d'effets REMISE en argument :
# une entree dont l'action est « aucune » ET dont l'etat vise est l'ecran d'ou elle est
# activee.
#
# LE PARAMETRE EST LA RAISON D'ETRE DE CETTE FONCTION. Sur les menus reels le compte
# vaut 0, donc le corps de la boucle n'est JAMAIS atteint : un compteur qui ne compte
# jamais rien n'est prouve par rien — ni son increment, ni sa condition. En recevant la
# liste, il devient exercable sur une liste qui CONTIENT une entree sans effet, et le
# sens de son increment comme les deux membres de sa condition deviennent falsifiables.
static func compter_sans_effet(effets: Array, etat_courant: int) -> int:
	var n: int = 0
	for eff in effets:
		if eff["action"] == ACTION_AUCUNE and eff["etat"] == etat_courant:
			n += 1
	return n


static func entrees_sans_effet_titre() -> int:
	return compter_sans_effet(effets_titre(), App.Etat.TITRE)


static func entrees_sans_effet_pause() -> int:
	return compter_sans_effet(effets_pause(), App.Etat.PAUSE)
