# dash.gd — MODE D'ACCESSIBILITE « dash » (lignes dash.dedicated_intent,
# dash.disabled_inert, dash.declared_effects).
#
# Declenche sur son intention DEDIEE, distincte des quatre intentions de direction :
# aucune direction ne dashe, aucun dash ne deplace par le canal des directions. Produit
# un BUDGET DE PAS pour le tick, JAMAIS un deplacement — c'est player_movement qui
# deplace, et sa regle de butee est la meme quel que soit le budget.
#
# Logique PURE. Depend de params, settings et input_intents.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")

# DECLARATION, grandeur par grandeur, de ce que le dash change. C'est une DONNEE
# confrontee a la mesure de proof_harness, jamais une note de commentaire.
const MODIFIE := "MODIFIE"
const INCHANGE := "INCHANGE_PAR_CONCEPTION"
const GRANDEURS: Array = [
	"vitesse_joueur", "delai_avant_dash", "comportement_murs", "comportement_fantomes",
]
const EFFETS_DECLARES: Dictionary = {
	"vitesse_joueur": MODIFIE,
	"delai_avant_dash": MODIFIE,
	# STRUCTURELLEMENT inchanges : ce module ne decide ni butee ni contact. La mesure
	# CONFIRME la declaration, elle ne la fonde pas.
	"comportement_murs": INCHANGE,
	"comportement_fantomes": INCHANGE,
}

const INTENTION_DEDIEE: int = Intents.Intention.DASH


# L'intention recue est-elle la demande de dash ? Une intention de direction ne dashe
# jamais — la separation est un test d'egalite, pas une convention de nommage.
static func est_demande(intention: int) -> bool:
	return intention == INTENTION_DEDIEE


# Le dash est-il DISPONIBLE a cet instant ? Actif dans les reglages, recharge ecoulee.
static func disponible(s) -> bool:
	return s.dash_actif and s.dash_recharge <= 0


# BUDGET DE PAS du tick, et effet sur la recharge. DASH DESACTIVE : la fonction est
# INERTE — elle rend le budget normal et NE TOUCHE A RIEN dans l'etat, pas meme un
# compteur. C'est une propriete d'egalite stricte de traces, pas une absence d'effet
# visible.
static func appliquer(s, demande: bool) -> int:
	if not s.dash_actif:
		return P.PAS_NORMAL
	if s.dash_recharge > 0:
		s.dash_recharge -= 1
	if demande and disponible(s):
		s.dash_recharge = P.RECHARGE_DASH_TICKS
		return P.PAS_DASH
	return P.PAS_NORMAL


# Grandeurs DECLAREES modifiees / inchangees — lues par le harnais de mesure.
static func grandeurs_modifiees() -> Array:
	var sortie: Array = []
	for g in GRANDEURS:
		if EFFETS_DECLARES[g] == MODIFIE:
			sortie.append(g)
	return sortie


static func grandeurs_inchangees() -> Array:
	var sortie: Array = []
	for g in GRANDEURS:
		if EFFETS_DECLARES[g] == INCHANGE:
			sortie.append(g)
	return sortie


static func mode_autorise_dash(mode: int) -> bool:
	return Reglages.valide(mode)
