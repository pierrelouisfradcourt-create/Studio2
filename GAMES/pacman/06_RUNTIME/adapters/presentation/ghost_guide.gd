# ghost_guide.gd — LE COMPORTEMENT DES QUATRE FANTOMES, TRANSMIS AU JOUEUR
# (V4, cause racine P3).
#
# DEFAUT MESURE (playtest Pierre) : les quatre ciblages EXISTENT reellement dans
# 05_SYSTEMS/ghost_targeting/ghost_targeting.gd et sont prouves depuis V1 — mais rien
# dans le jeu ne les dit. Ce n'est donc pas un defaut de code : c'est une information
# produite et jamais transmise. La correction appartient a la PRESENTATION.
#
# REGLE DE VERITE : ce module ne decrit QUE ce que `cible_poursuite()` fait, et il tient
# ses nombres de la SOURCE (`Targeting.AVANCE_ROSE`, `AVANCE_CYAN`, `SEUIL_ORANGE`),
# jamais d'une recopie. Un texte qui recopierait les valeurs pourrait mentir sans qu'aucune
# mesure ne le voie ; ici, changer la regle change la phrase. Le Pac-Man d'arcade n'est
# PAS la reference : le code fait foi.
#
# ADAPTATEUR : il lit la logique pure, la logique pure ne le connait pas. Aucune couleur
# n'est ecrite ici — la teinte des fantomes vit dans le descripteur de palette.
extends RefCounted

const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

const TITRE := "FANTOMES"

# Noms d'usage des quatre fantomes, dans l'ORDRE NOMINATIF declare par le ciblage.
const NOMS: Array = ["ROUGE", "ROSE", "CYAN", "ORANGE"]

# Phrases de comportement. Chacune est ASSORTIE, dans la preuve, d'une verification de la
# propriete qu'elle annonce contre un appel reel a `cible_poursuite()`.
const PHRASE_ROUGE := "vise ta case, poursuite directe"
const PHRASE_ROSE := "vise la case %d devant toi"
const PHRASE_CYAN := "vise le point %d devant toi, double depuis le rouge"
const PHRASE_ORANGE := "te poursuit au-dela de %d cases, sinon rentre a son coin"
# Comportement commun aux quatre, hors poursuite : ils regagnent leur coin.
const PHRASE_DISPERSION := "En dispersion, chacun regagne SON coin."

const SEPARATEUR := " : "


# AVANCE de ciblage propre a un fantome, LUE dans le module de ciblage. La valeur 0 dit
# « ce fantome ne regarde pas devant toi », elle n'est pas un defaut de renseignement.
static func avance(index: int) -> int:
	if index == Targeting.ROSE:
		return Targeting.AVANCE_ROSE
	if index == Targeting.CYAN:
		return Targeting.AVANCE_CYAN
	return 0


# SEUIL de bascule propre a un fantome, LU dans le module de ciblage. 0 = pas de seuil.
static func seuil(index: int) -> int:
	if index == Targeting.ORANGE:
		return Targeting.SEUIL_ORANGE
	return 0


static func nom(index: int) -> String:
	if index < 0 or index >= NOMS.size():
		return ""
	return NOMS[index]


# COMPORTEMENT decrit d'un fantome. Les nombres viennent du ciblage, jamais du texte.
static func comportement(index: int) -> String:
	if index == Targeting.ROUGE:
		return PHRASE_ROUGE
	if index == Targeting.ROSE:
		return PHRASE_ROSE % Targeting.AVANCE_ROSE
	if index == Targeting.CYAN:
		return PHRASE_CYAN % Targeting.AVANCE_CYAN
	if index == Targeting.ORANGE:
		return PHRASE_ORANGE % Targeting.SEUIL_ORANGE
	return ""


static func ligne(index: int) -> String:
	if comportement(index) == "":
		return ""
	return nom(index) + SEPARATEUR + comportement(index)


# Toutes les lignes du guide, dans l'ordre nominatif, plus la mention de dispersion.
static func lignes() -> Array:
	var sortie: Array = []
	for i in range(Targeting.NOMBRE_FANTOMES):
		sortie.append(ligne(i))
	sortie.append(PHRASE_DISPERSION)
	return sortie


# Nombre de fantomes DONT LE COMPORTEMENT N'EST PAS TRANSMIS. La valeur attendue vaut
# exactement 0 — avant V4 elle valait 4, aucune ligne n'existant.
static func fantomes_sans_description() -> int:
	var n: int = 0
	for i in range(Targeting.NOMBRE_FANTOMES):
		if comportement(i) == "":
			n += 1
	return n


# Nombre de PAIRES DE DESCRIPTIONS IDENTIQUES : quatre fantomes decrits par la meme
# phrase ne transmettraient rien. La valeur attendue vaut exactement 0.
static func paires_identiques() -> int:
	var n: int = 0
	for i in range(Targeting.NOMBRE_FANTOMES):
		for j in range(i + 1, Targeting.NOMBRE_FANTOMES):
			if comportement(i) == comportement(j):
				n += 1
	return n


# Couleur nominative d'un fantome, DEMANDEE a la palette : le guide nomme la teinte que
# le joueur voit a l'ecran, il n'en declare aucune.
static func couleur(index: int) -> Color:
	return Palette.couleur_fantome(index)
