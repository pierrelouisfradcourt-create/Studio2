# presentation.gd — ELEMENTS AFFICHES du jeu en cours (lignes presentation.dash_readability,
# presentation.level_number, presentation.readable_elements, core.render).
#
# Ne calcule RIEN : il lit le SEUL releve observable produit par game_state/observable.gd,
# au MEME tick que le lecteur exterieur — deux lectures d'une source unique, jamais deux
# calculs paralleles qui pourraient diverger.
#
# Toutes les couleurs viennent du descripteur de palette unique.
extends RefCounted

const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

# --- NUMERO DE NIVEAU ------------------------------------------------------------
const ETIQUETTE_NIVEAU := "NIVEAU "


static func texte_niveau(releve: Dictionary) -> String:
	return ETIQUETTE_NIVEAU + str(releve["niveau"])


# Relit le nombre affiche : c'est CETTE fonction qui rend l'egalite « chiffre a l'ecran
# == niveau de l'etat » verifiable mecaniquement, plutot que par relecture humaine.
static func relire_niveau(texte: String) -> int:
	var debut: int = texte.find(ETIQUETTE_NIVEAU)
	if debut < 0:
		return -1
	var reste: String = texte.substr(debut + ETIQUETTE_NIVEAU.length())
	var chiffres := ""
	for i in range(reste.length()):
		var c: String = reste[i]
		if c >= "0" and c <= "9":
			chiffres += c
		else:
			break
	if chiffres.is_empty():
		return -1
	return int(chiffres)


# --- LISIBILITE DU DASH ----------------------------------------------------------
const MENTION_DASH_PRET := "DASH PRET"
const MENTION_DASH_RECHARGE := "DASH "
const MENTION_DASH_ABSENT := ""


# Le dash est-il DISPONIBLE selon le seul releve ?
static func dash_pret(releve: Dictionary) -> bool:
	return bool(releve["dash_actif"]) and int(releve["dash_recharge"]) <= 0


# Indication A L'ECRAN de la disponibilite du dash — portee par l'affichage, pas
# seulement par l'etat : sans elle, la capacite serait deja acquise par l'etat expose
# et ne mesurerait rien de neuf.
static func mention_dash(releve: Dictionary) -> String:
	if not bool(releve["dash_actif"]):
		return MENTION_DASH_ABSENT
	if dash_pret(releve):
		return MENTION_DASH_PRET
	return MENTION_DASH_RECHARGE + str(releve["dash_recharge"])


static func couleur_dash(releve: Dictionary) -> Color:
	if dash_pret(releve):
		return Palette.DASH_PRET
	return Palette.DASH_RECHARGE


# --- QUATRE ELEMENTS INTERROGEABLES ----------------------------------------------
# Ce qui se mange, ce qui se fuit, ce qui arrive quand une carte est videe, comment la
# partie se termine. Chacun a une REPRESENTATION A L'ECRAN : le nombre d'elements sans
# representation vaut exactement 0.
const ELEMENT_A_MANGER := "a_manger"
const ELEMENT_A_FUIR := "a_fuir"
const ELEMENT_CARTE_VIDEE := "carte_videe"
const ELEMENT_FIN_DE_PARTIE := "fin_de_partie"
const ELEMENTS: Array = [
	ELEMENT_A_MANGER, ELEMENT_A_FUIR, ELEMENT_CARTE_VIDEE, ELEMENT_FIN_DE_PARTIE,
]


# Representation affichee de chaque element, construite depuis le releve. Une chaine
# vide signale une representation ABSENTE — c'est ce que le comptage releve.
static func representation(element: String, releve: Dictionary) -> String:
	if element == ELEMENT_A_MANGER:
		return "PASTILLES " + str(releve["restantes"])
	if element == ELEMENT_A_FUIR:
		return String(releve["mode"])
	if element == ELEMENT_CARTE_VIDEE:
		return texte_niveau(releve)
	if element == ELEMENT_FIN_DE_PARTIE:
		return "VIES " + str(releve["vies"])
	return ""


static func elements_sans_representation(releve: Dictionary) -> int:
	var n: int = 0
	for e in ELEMENTS:
		if representation(e, releve) == "":
			n += 1
	return n


# Ligne complete du bandeau V2 : niveau, dash, et les elements interrogeables.
static func bandeau(releve: Dictionary) -> String:
	var morceaux: Array = [texte_niveau(releve)]
	var dash: String = mention_dash(releve)
	if dash != "":
		morceaux.append(dash)
	for e in ELEMENTS:
		morceaux.append(representation(e, releve))
	return "  ".join(morceaux)
